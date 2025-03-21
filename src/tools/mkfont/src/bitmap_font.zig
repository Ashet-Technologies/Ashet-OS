const std = @import("std");
const schema = @import("schema.zig");
const zigimg = @import("zigimg");

pub fn validate(font: schema.BitmapFontFile) !bool {
    var ok = true;
    if (font.defaults.index != null) {
        std.log.err("defaults.index is not allowed to be set!", .{});
        ok = false;
    }

    for (0x20..0x7F) |codepoint| {
        const ascii: u7 = @intCast(codepoint);
        if (!font.glyphs.contains(ascii)) {
            std.log.warn("Font is missing printable ASCII character '{}' (0x{X:0>2})", .{
                std.zig.fmtEscapes(&.{ascii}),
                ascii,
            });
        }
    }

    return ok;
}

pub fn generate(
    allocator: std.mem.Allocator,
    file: std.fs.File,
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

    var glyph_bitmaps: std.AutoArrayHashMap(u21, Bitmap) = .init(allocator);
    defer glyph_bitmaps.deinit();

    var glyph_bitmap_arena: std.heap.ArenaAllocator = .init(allocator);
    defer glyph_bitmap_arena.deinit();

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
        const shrink_dx = @min(width, min_x - cell_x0);
        const shrink_dy = @min(height, min_y - cell_y0);

        const column_stride = vpixels_to_bytes(height);
        const byte_size = width * column_stride;

        const bits = try glyph_bitmap_arena.allocator().alloc(u8, byte_size);
        @memset(bits, 0);
        if (width > 0 and height > 0) {
            for (min_y..max_y) |y| {
                for (min_x..max_x) |x| {
                    const gx = x - min_x;
                    const gy = y - min_y;
                    const index = gx * column_stride + (gy / 8);
                    const bit: u3 = @intCast(gy % 8);
                    const mask: u8 = @as(u8, 1) << bit;

                    const pix = get_pixel(image, x, y);
                    if (is_glyph_body(select_pixels, pix)) {
                        bits[index] |= mask;
                    }
                }
            }
        } else {
            std.debug.assert(bits.len == 0);
        }

        var fmt: [8]u8 = undefined;
        const len = std.unicode.utf8Encode(codepoint, &fmt) catch @panic("implementation bug");

        std.log.info("U+{X:0>5} ('{}') => w={} h={} dx={} dy={} bits={}", .{
            codepoint,
            std.unicode.fmtUtf8(fmt[0..len]),
            width,
            height,
            shrink_dx,
            shrink_dy,
            std.fmt.fmtSliceHexUpper(bits),
        });
        std.log.info("  x0={} x1={} y0={} y1={}", .{
            cell_x0,
            cell_x1,
            cell_y0,
            cell_y1,
        });
        std.log.info("  x0={} x1={} y0={} y1={}", .{
            min_x,
            max_x,
            min_y,
            max_y,
        });

        var dump_buffer: [128]u8 = undefined;
        if (dump_buffer.len >= width) {
            for (0..height) |y| {
                var fbs = std.io.fixedBufferStream(&dump_buffer);
                const writer = fbs.writer();

                for (0..width) |x| {
                    const byte_index = x * column_stride + (y / 8);
                    const bit: u3 = @intCast(y % 8);
                    const mask: u8 = @as(u8, 1) << bit;

                    if ((bits[byte_index] & mask) != 0) {
                        writer.writeByte('X') catch {};
                    } else {
                        writer.writeByte(' ') catch {};
                    }
                }

                std.log.info("|{s}|", .{fbs.getWritten()});
            }

            std.log.info("", .{});
        }

        try glyph_bitmaps.put(codepoint, .{
            .width = @intCast(width),
            .height = @intCast(height),
            .offset_x = @intCast(shrink_dx),
            .offset_y = @intCast(shrink_dy),
            .bits = bits,
        });
    }

    const writer = file.writer();

    // Write file header:
    try writer.writeInt(u32, 0xcb3765be, .little);
    try writer.writeInt(u32, font.line_height, .little);
    try writer.writeInt(u32, @intCast(font.glyphs.count()), .little);

    // Write `glyph_meta` array:
    for (font.glyphs.keys(), font.glyphs.values()) |codepoint, glyph| {
        const Meta = packed struct(u32) {
            codepoint: u24,
            advance: u8,
        };
        const meta: Meta = .{
            .codepoint = codepoint,
            .advance = glyph.advance orelse font.defaults.advance orelse @panic("missing validation!"),
        };
        const meta_value: u32 = @bitCast(meta);

        try writer.writeInt(u32, meta_value, .little);
    }

    var glyph_sizes: std.AutoArrayHashMap(u21, struct { u32, usize }) = .init(allocator);
    defer glyph_sizes.deinit();

    // Write `glyph_offsets` array:
    {
        var base_offset: u32 = 0;
        for (font.glyphs.keys()) |codepoint| {
            const glyph_bitmap = glyph_bitmaps.get(codepoint).?;
            std.debug.assert(glyph_bitmap.bits.len == glyph_bitmap.width * vpixels_to_bytes(glyph_bitmap.height));

            const encoded_glyph_size: u32 = @intCast(4 + glyph_bitmap.bits.len);

            try writer.writeInt(u32, base_offset, .little);

            try glyph_sizes.put(codepoint, .{ base_offset, encoded_glyph_size });

            base_offset += encoded_glyph_size;
        }
    }

    // Write `glyphs` data array:
    {
        const start = try writer.context.getPos();
        for (font.glyphs.keys()) |codepoint| {
            const expected_offset, const expected_size = glyph_sizes.get(codepoint).?;
            const glyph_bitmap = glyph_bitmaps.get(codepoint).?;

            const offset = try writer.context.getPos();
            std.debug.assert(offset - start == expected_offset);

            try writer.writeInt(u8, glyph_bitmap.width, .little);
            try writer.writeInt(u8, glyph_bitmap.height, .little);
            try writer.writeInt(i8, glyph_bitmap.offset_x, .little);
            try writer.writeInt(i8, glyph_bitmap.offset_y, .little);
            try writer.writeAll(glyph_bitmap.bits);

            const end = try writer.context.getPos();
            std.debug.assert(end - offset == expected_size);
        }
    }
}

fn vpixels_to_bytes(vpix: usize) usize {
    return (vpix + 7) / 8;
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

const Bitmap = struct {
    // Actual glyph size
    width: u8,
    height: u8,
    // delta to glyph top-left
    offset_x: i8,
    offset_y: i8,
    // column-major bitmap, LSB=Top to MSB=Bottom
    bits: []u8,
};

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

            gop.value_ptr.* = try zigimg.Image.fromFile(ic.arena.allocator(), &file);
        }
        return gop.value_ptr;
    }
};
