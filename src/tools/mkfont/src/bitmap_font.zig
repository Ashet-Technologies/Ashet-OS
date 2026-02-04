const std = @import("std");
const schema = @import("schema.zig");
const zigimg = @import("zigimg");

const bmp_font_gen = @import("bmp_font_gen.zig");

pub fn validate(font: schema.BitmapFontFile) !bool {
    var ok = true;
    if (font.defaults.index != null) {
        std.log.err("defaults.index is not allowed to be set!", .{});
        ok = false;
    }

    for (0x20..0x7F) |codepoint| {
        const ascii: u7 = @intCast(codepoint);
        if (!font.glyphs.contains(ascii)) {
            std.log.warn("Font is missing printable ASCII character '{f}' (0x{X:0>2})", .{
                std.zig.fmtString(&.{ascii}),
                ascii,
            });
        }
    }

    return ok;
}

pub fn generate(
    allocator: std.mem.Allocator,
    file_writer: *std.fs.File.Writer,
    root_dir: std.fs.Dir,
    font: *schema.BitmapFontFile,
) !void {
    // Glyphs must be sorted in the font:
    font.glyphs.sort(struct {
        glyphs: *std.AutoArrayHashMap(u21, schema.BitmapFontFile.Glyph),
        pub fn lessThan(self: @This(), lhs_index: usize, rhs_index: usize) bool {
            return self.glyphs.keys()[lhs_index] < self.glyphs.keys()[rhs_index];
        }
    }{
        .glyphs = &font.glyphs,
    });

    // Fetch all images ahead of time:
    var image_cache: ImageCache = .{ .arena = .init(allocator), .root = root_dir };
    defer image_cache.deinit();

    if (font.defaults.image_file) |image_file| {
        _ = try image_cache.get_or_load(image_file);
    }

    for (font.glyphs.values()) |glyph| {
        if (glyph.image_file) |image_file| {
            _ = try image_cache.get_or_load(image_file);
        }
    }

    // Compute all output files:

    var builder: bmp_font_gen.Builder = .init(allocator);
    defer builder.deinit();

    for (font.glyphs.keys(), font.glyphs.values()) |codepoint, glyph| {
        const image_file = glyph.image_file orelse font.defaults.image_file orelse @panic("missing validation");
        const image = try image_cache.get_or_load(image_file);
        const select_pixels = glyph.select_pixels orelse font.defaults.select_pixels orelse @panic("missing validation");

        const maybe_index = glyph.index;
        const maybe_atlas = glyph.atlas orelse font.defaults.atlas;

        const cell_x0, const cell_y0, const cell_x1, const cell_y1 = if (maybe_index) |index| blk: {
            const atlas = maybe_atlas orelse @panic("missing validation for index => atlas!");

            const column = index % atlas.row_length;
            const row = index / atlas.row_length;

            const dx = atlas.margin + atlas.cell_width * column + atlas.cell_padding;
            const dy = atlas.margin + atlas.cell_height * row + atlas.cell_padding;

            break :blk .{
                dx,
                dy,
                dx + atlas.cell_width - 2 * atlas.cell_padding,
                dy + atlas.cell_height - 2 * atlas.cell_padding,
            };
        } else .{ 0, 0, image.width, image.height };

        var min_x: usize = std.math.maxInt(usize);
        var max_x: usize = 0;
        var min_y: usize = std.math.maxInt(usize);
        var max_y: usize = 0;

        std.debug.assert(cell_x0 <= cell_x1);
        std.debug.assert(cell_y0 <= cell_y1);

        for (cell_y0..cell_y1) |y| {
            for (cell_x0..cell_x1) |x| {
                const pix = get_pixel(image, x, y);
                if (is_glyph_body(select_pixels, pix)) {
                    min_x = @min(min_x, x);
                    max_x = @max(max_x, x + 1);
                    min_y = @min(min_y, y);
                    max_y = @max(max_y, y + 1);
                }
            }
        }

        const width = max_x -| min_x;
        const height = max_y -| min_y;

        // we must use the cell size here, not the width of the emitted graphic.
        // Consider an "_" glyph which has a height of 1, but a dy of 6
        const shrink_dx = @min(cell_x1 - cell_x0, min_x - cell_x0);
        const shrink_dy = @min(cell_y1 - cell_y0, min_y - cell_y0);

        const out_glyph = try builder.add(codepoint, .{
            .advance = glyph.advance orelse font.defaults.advance orelse @panic("missing validation!"),
            .width = width,
            .height = height,
            .offset_x = @intCast(shrink_dx),
            .offset_y = @intCast(shrink_dy),
        });

        if (width > 0 and height > 0) {
            for (min_y..max_y) |y| {
                for (min_x..max_x) |x| {
                    const gx = x - min_x;
                    const gy = y - min_y;

                    const pix = get_pixel(image, x, y);
                    out_glyph.set_pixel(gx, gy, .from_bool(is_glyph_body(select_pixels, pix)));
                }
            }
        }

        // var fmt: [8]u8 = undefined;
        // const len = std.unicode.utf8Encode(codepoint, &fmt) catch @panic("implementation bug");

        // std.debug.print("U+{X:0>5} ('{}') => w={} h={} dx={} dy={} bits={}\n", .{
        //     codepoint,
        //     std.unicode.fmtUtf8(fmt[0..len]),
        //     width,
        //     height,
        //     shrink_dx,
        //     shrink_dy,
        //     std.fmt.fmtSliceHexUpper(out_glyph.bits),
        // });
        // std.debug.print("  x0={} x1={} y0={} y1={}\n", .{
        //     cell_x0,
        //     cell_x1,
        //     cell_y0,
        //     cell_y1,
        // });
        // std.debug.print("  x0={} x1={} y0={} y1={}\n", .{
        //     min_x,
        //     max_x,
        //     min_y,
        //     max_y,
        // });

        // out_glyph.dump("  ");
    }

    try bmp_font_gen.render(allocator, file_writer, builder, .{
        .line_height = font.line_height,
    });
}

fn get_pixel(img: *const zigimg.Image, x: usize, y: usize) zigimg.color.Colorf32 {
    var iter = img.iterator();
    iter.current_index = y * img.width + x;
    return iter.next().?;
}

fn is_glyph_body(selector: schema.BitmapFontFile.SelectPixel, pix: zigimg.color.Colorf32) bool {
    const gray_level = (pix.r + pix.g + pix.b) / 3;

    return switch (selector) {
        .@"opaque" => (pix.a >= 0.5),
        .white => (gray_level >= 0.5),
        .black => (gray_level <= 0.5),
    };
}

const ImageCache = struct {
    arena: std.heap.ArenaAllocator,
    root: std.fs.Dir,

    images: std.StringHashMapUnmanaged(zigimg.Image) = .empty,

    pub fn deinit(ic: *ImageCache) void {
        ic.arena.deinit();
        ic.* = undefined;
    }

    pub fn get_or_load(ic: *ImageCache, path: []const u8) !*zigimg.Image {
        const gop = try ic.images.getOrPut(ic.arena.allocator(), path);
        if (!gop.found_existing) {
            errdefer _ = ic.images.remove(path);

            var file = try ic.root.openFile(path, .{});
            defer file.close();

            var image_read_buff: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
            gop.value_ptr.* = try zigimg.Image.fromFile(ic.arena.allocator(), file, &image_read_buff);
        }
        return gop.value_ptr;
    }
};
