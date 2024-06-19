const std = @import("std");
const zigimg = @import("zigimg");
const abi = @import("ashet-abi");
const args_parser = @import("args");

const Rgba32 = zigimg.color.Rgba32;

const Palette = []Rgba32;

const loadPaletteFile = @import("lib/palette.zig").loadPaletteFile;

fn isTransparent(c: zigimg.color.Colorf32) bool {
    return c.a < 0.5;
}

const CliOptions = struct {
    palette: ?[]const u8 = null,
    geometry: ?[]const u8 = null,
    output: ?[]const u8 = null,
    @"color-count": ?u8 = null,

    pub const shorthands = .{
        .p = "palette",
        .g = "geometry",
        .o = "output",
        .c = "color-count",
    };
};

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    var cli = args_parser.parseForCurrentProcess(CliOptions, arena.allocator(), .print) catch return 1;
    defer cli.deinit();

    if (cli.positionals.len != 1) {
        @panic("requires a single positional argument!");
    }

    const input_file_name = cli.positionals[0];
    const output_file_name = cli.options.output orelse @panic("requires output file name");

    if ((cli.options.palette != null) == (cli.options.@"color-count" != null)) {
        @panic("Either palette or size must be set!");
    }

    const size: [2]usize = if (cli.options.geometry) |spec| blk: {
        var it = std.mem.split(u8, spec, "x");
        const w = try std.fmt.parseInt(usize, it.next().?, 10);
        const h = try std.fmt.parseInt(usize, it.next().?, 10);
        break :blk .{ w, h };
    } else .{ 64, 64 };

    // std.log.info("processing {s}", .{input_file_name});

    var raw_image = try zigimg.Image.fromFilePath(arena.allocator(), input_file_name);
    if (raw_image.width != size[0] or raw_image.height != size[1]) {
        std.debug.panic("image must be {}x{}", .{ size[0], size[1] });
    }

    const palette = if (cli.options.palette) |palette_file|
        try loadPaletteFile(arena.allocator(), palette_file)
    else blk: {
        const color_count = cli.options.@"color-count" orelse {
            @panic("if no palette is specified, --color-count <num> must be passed.");
        };

        // compute palette
        // var quantizer = zigimg.OctTreeQuantizer.init(arena.allocator());
        // {
        //     var src_pixels = raw_image.iterator();
        //     while (src_pixels.next()) |src_color| {
        //         if (!isTransparent(src_color)) {
        //             try quantizer.addColor(reduceTo565(src_color));
        //         } else {
        //             // don't count transparent pixels into the palette
        //             // everything transparent is considered index=0 by definition,
        //             // so we don't need to use these colors
        //         }
        //     }
        // }

        var palettes = std.BoundedArray(Palette, 8){};

        if (quantizeOctree(arena.allocator(), color_count, raw_image)) |octree_palette| {
            try palettes.append(octree_palette);
        } else |err| {
            std.log.err("failed to generate octree palette: {}", .{err});
        }

        if (quantizeCountColors(arena.allocator(), color_count, raw_image)) |fixed_set_palette| {
            try palettes.append(fixed_set_palette);
        } else |err| {
            std.log.err("failed to generate fixed set palette: {}", .{err});
        }

        const available_palettes = palettes.slice();
        if (available_palettes.len == 0)
            @panic("failed to generate any fitting palette!");

        const min_quality = computePaletteQuality(available_palettes[0], raw_image);
        var palette = available_palettes[0];

        for (available_palettes[1..]) |pal| {
            var quality = computePaletteQuality(pal, raw_image);
            if (quality < min_quality) {
                quality = min_quality;
                palette = pal;
            }
        }

        break :blk palette;
    };

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
            if (isTransparent(src_color)) {
                bitmap[i] = 0xFF; // transparent
            } else {
                bitmap[i] = @as(u8, @intCast(getBestMatch(palette, reduceTo565(src_color))));
            }
        }
    }

    var limit: u8 = 0;
    var transparency = false;
    for (bitmap) |c| {
        if (c >= (palette.len + 1) and c != 0xFF) @panic("color index out of range!");
        if (c != 0xFF)
            limit = @max(limit, c);
        if (c == 0xFF)
            transparency = true;
    }
    limit += 1; // compute palette size

    // compute bitmap
    var out_file = try std.fs.cwd().createFile(output_file_name, .{});
    defer out_file.close();

    var buffered_writer = std.io.bufferedWriter(out_file.writer());
    var writer = buffered_writer.writer();

    try writer.writeInt(u32, 0x48198b74, .little);
    try writer.writeInt(u16, @as(u16, @intCast(raw_image.width)), .little);
    try writer.writeInt(u16, @as(u16, @intCast(raw_image.height)), .little);
    try writer.writeInt(u16, if (transparency) @as(u16, 0x0001) else 0x0000, .little); // flags, enable transparency
    try writer.writeInt(u8, limit, .little); // palette size
    try writer.writeInt(u8, 0xFF, .little); // transparent

    try writer.writeAll(bitmap);

    for (palette) |color| {
        const rgb565 = zigimg.color.Rgb565.fromU32Rgba(color.toU32Rgba());
        const abi_color = abi.Color{
            .r = rgb565.r,
            .g = rgb565.g,
            .b = rgb565.b,
        };
        try writer.writeInt(u16, abi_color.toU16(), .little);
    }

    try buffered_writer.flush();

    return 0;
}

fn quantizeCountColors(allocator: std.mem.Allocator, palette_size: usize, image: zigimg.Image) !Palette {
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

    if (color_map.keys().len > palette_size)
        return error.TooManyColors;

    const palette = try allocator.alloc(Rgba32, palette_size);
    std.mem.copyForwards(Rgba32, palette, color_map.keys());
    return palette;
}

fn quantizeOctree(allocator: std.mem.Allocator, palette_size: u32, image: zigimg.Image) !Palette {
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

    const palette_buffer = try allocator.alloc(Rgba32, palette_size);
    errdefer allocator.free(palette_buffer);

    const octree_palette = quantizer.makePalette(palette_size, palette_buffer);

    std.debug.assert(palette_buffer.ptr == octree_palette.ptr);

    return palette_buffer[0..octree_palette.len];
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
    // implemented after
    // https://en.wikipedia.org/wiki/Color_difference#sRGB
    //

    const Variants = enum {
        euclidean,
        redmean_digital,
        redmean_smooth,
    };

    const variant = Variants.redmean_smooth;

    const dr = @as(i32, a.r) - @as(i32, b.r);
    const dg = @as(i32, a.g) - @as(i32, b.g);
    const db = @as(i32, a.b) - @as(i32, b.b);

    switch (variant) {
        .euclidean => return @as(u32, @intCast(2 * dr * dr + 4 * dg * dg + 3 * db * db)),
        .redmean_digital => if ((@as(u32, a.r) + b.r) / 2 < 128) {
            return @as(u32, @intCast(2 * dr * dr + 4 * dg * dg + 3 * db * db));
        } else {
            return @as(u32, @intCast(3 * dr * dr + 4 * dg * dg + 2 * db * db));
        },
        .redmean_smooth => {
            const dhalf = @as(f32, @floatFromInt((@as(u32, a.r) + b.r) / 2));
            const r2 = (2.0 + dhalf / 256) * @as(f32, @floatFromInt(dr * dr));
            const g2 = 4.0 * @as(f32, @floatFromInt(dg * dg));
            const b2 = (2.0 + (255.0 - dhalf) / 256) * @as(f32, @floatFromInt(db * db));
            return @as(u32, @intFromFloat(10.0 * (r2 + g2 + b2)));
        },
    }
}

fn getBestMatch(pal: Palette, col: Rgba32) usize {
    var best: usize = 0;
    var threshold: u32 = colorDist(pal[0], col);
    for (pal[1..], 0..) |color, index| {
        const dist = colorDist(color, col);
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
