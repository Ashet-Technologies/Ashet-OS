const std = @import("std");
const zigimg = @import("zigimg");
const abi = @import("ashet-abi");

const Rgba32 = zigimg.color.Rgba32;

const Palette = [15]Rgba32;

fn isTransparent(c: zigimg.color.Colorf32) bool {
    return c.a < 0.5;
}

const palette_template: Palette = [1]Rgba32{.{ .r = 0xFF, .g = 0x00, .b = 0xFF, .a = 0xFF }} ** 15;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    const args = try std.process.argsAlloc(arena.allocator());
    if (args.len < 3 or args.len > 4) {
        @panic("requires 2 args!");
    }

    const size: [2]usize = if (args.len >= 4) blk: {
        const spec = args[3];
        var it = std.mem.split(u8, spec, "x");
        const w = try std.fmt.parseInt(usize, it.next().?, 10);
        const h = try std.fmt.parseInt(usize, it.next().?, 10);
        break :blk .{ w, h };
    } else .{ 64, 64 };

    std.log.info("processing {s}", .{args[1]});

    var raw_image = try zigimg.Image.fromFilePath(arena.allocator(), args[1]);
    if (raw_image.width != size[0] or raw_image.height != size[1]) {
        std.debug.panic("image must be {}x{}", .{ size[0], size[1] });
    }

    // compute palette
    var quantizer = zigimg.OctTreeQuantizer.init(arena.allocator());
    {
        var src_pixels = raw_image.iterator();
        while (src_pixels.next()) |src_color| {
            if (!isTransparent(src_color)) {
                try quantizer.addColor(reduceTo565(src_color));
            } else {
                // don't count transparent pixels into the palette
                // everything transparent is considered index=0 by definition,
                // so we don't need to use these colors
            }
        }
    }

    var palettes = std.BoundedArray(Palette, 8){};

    if (quantizeOctree(arena.allocator(), raw_image)) |octree_palette| {
        try palettes.append(octree_palette);
    } else |err| {
        std.log.err("failed to generate octree palette: {}", .{err});
    }

    if (quantizeCountColors(arena.allocator(), raw_image)) |fixed_set_palette| {
        try palettes.append(fixed_set_palette);
    } else |err| {
        std.log.err("failed to generate fixed set palette: {}", .{err});
    }

    const available_palettes = palettes.slice();
    if (available_palettes.len == 0)
        @panic("failed to generate any fitting palette!");

    var min_quality = computePaletteQuality(available_palettes[0], raw_image);
    var palette = available_palettes[0];

    for (available_palettes[1..]) |pal| {
        var quality = computePaletteQuality(pal, raw_image);
        if (quality < min_quality) {
            quality = min_quality;
            palette = pal;
        }
    }

    // std.log.info("palette quality: {}", .{computePaletteQuality(palette, raw_image)});
    // for (palette32) |pal, i| {
    //     std.log.info("0x{X} => #{X:0>2}{X:0>2}{X:0>2}", .{
    //         i, pal.r, pal.g, pal.b,
    //     });
    // }

    // map colors
    var bitmap: []u8 = try arena.allocator().alloc(u8, raw_image.width * raw_image.height);
    {
        var i: usize = 0;
        var src_pixels = raw_image.iterator();
        while (src_pixels.next()) |src_color| : (i += 1) {
            if (!isTransparent(src_color)) {
                bitmap[i] = 0x01 + @intCast(u8, getBestMatch(palette, reduceTo565(src_color)));
            } else {
                bitmap[i] = 0x00; // transparent
            }
        }
    }

    for (bitmap) |c| {
        if (c >= 16) @panic("color index out of range!");
    }

    // compute bitmap
    var out_file = try std.fs.cwd().createFile(args[2], .{});
    defer out_file.close();

    var buffered_writer = std.io.bufferedWriter(out_file.writer());
    var writer = buffered_writer.writer();

    try writer.writeAll(bitmap);

    for (palette) |color| {
        const rgb565 = zigimg.color.Rgb565.fromU32Rgba(color.toU32Rgba());
        const abi_color = abi.Color{
            .r = rgb565.r,
            .g = rgb565.g,
            .b = rgb565.b,
        };
        try writer.writeIntLittle(u16, abi_color.toU16());
    }

    try buffered_writer.flush();
}

fn quantizeCountColors(allocator: std.mem.Allocator, image: zigimg.Image) !Palette {
    var color_map = std.AutoArrayHashMap(Rgba32, void).init(allocator);
    defer color_map.deinit();

    var src_pixels = image.iterator();
    while (src_pixels.next()) |src_color| {
        if (!isTransparent(src_color)) {
            try color_map.put(reduceTo565(src_color), {});
        } else {
            // don't count transparent pixels into the palette
            // everything transparent is considered index=0 by definition,
            // so we don't need to use these colors
        }
    }

    if (color_map.keys().len > 15)
        return error.TooManyColors;

    var palette = palette_template;
    std.mem.copy(Rgba32, &palette, color_map.keys());
    return palette;
}

fn quantizeOctree(allocator: std.mem.Allocator, image: zigimg.Image) !Palette {
    var quantizer = zigimg.OctTreeQuantizer.init(allocator);
    defer quantizer.deinit();

    var src_pixels = image.iterator();
    while (src_pixels.next()) |src_color| {
        if (!isTransparent(src_color)) {
            try quantizer.addColor(reduceTo565(src_color));
        } else {
            // don't count transparent pixels into the palette
            // everything transparent is considered index=0 by definition,
            // so we don't need to use these colors
        }
    }

    var octree_palette_buffer = palette_template;
    const octree_palette = try quantizer.makePalette(15, &octree_palette_buffer);

    var palette = palette_template;
    std.mem.copy(Rgba32, &palette, octree_palette);
    return palette;
}

/// Computes the palette quality. Lower is better.
fn computePaletteQuality(palette: Palette, image: zigimg.Image) u64 {
    var sum: u64 = 0;

    var iter = image.iterator();
    while (iter.next()) |color| {
        if (!isTransparent(color)) {
            const index = getBestMatch(palette, reduceTo565(color));
            sum += colorDist(color.toRgba(u8), palette[index]);
        }
    }

    return sum;
}

fn reduceTo565(col: zigimg.color.Colorf32) Rgba32 {
    const rgb565 = zigimg.color.Rgb565.fromU32Rgba(col.toU32Rgba());
    return Rgba32.fromU32Rgb(rgb565.toU32Rgb());
}

fn colorDist(a: Rgba32, b: Rgba32) u32 {
    const dr = @as(i32, a.r) - @as(i32, b.r);
    const dg = @as(i32, a.g) - @as(i32, b.g);
    const db = @as(i32, a.b) - @as(i32, b.b);

    return @intCast(u32, dr * dr + dg * dg + db * db);
}

fn getBestMatch(pal: Palette, col: Rgba32) usize {
    var best: usize = 0;
    var threshold: u32 = colorDist(pal[0], col);
    for (pal[1..]) |color, index| {
        var dist = colorDist(color, col);
        if (dist < threshold) {
            threshold = dist;
            best = index + 1; // oof by one, as we iterate over pal[1..]
        }
    }
    return best;
}

// const MedianCutQuantizer = struct {
//     const Color = Rgba32;

//     const ColorContext = struct {
//         fn hash(a: Color, ctx: ColorContext) u32 {
//             return @bitCast(u32, a);
//         }
//         fn eql(a: Color, b: Color, ctx: ColorContext) bool {
//             return @bitCast(u32, a) == @bitCast(u32, b);
//         }
//     };

//     const Map = std.AutoArrayHashMap(Color, usize, void, ColorContext, false);

//     color_counts:
// };
