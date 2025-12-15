const std = @import("std");

pub const FontInfo = struct {
    line_height: u32,
};

pub const Pixel = enum(u1) {
    unset = 0,
    set = 1,

    pub fn from_bool(b: bool) Pixel {
        return @enumFromInt(@intFromBool(b));
    }
};

pub const Glyph = struct {
    advance: u8,

    // Actual glyph size
    width: u8,
    height: u8,
    // delta to glyph top-left
    offset_x: i8,
    offset_y: i8,
    // column-major bitmap, LSB=Top to MSB=Bottom
    bits: []u8,

    pub fn set_pixel(glyph: Glyph, x: usize, y: usize, value: Pixel) void {
        const row_stride = pixels_to_bytes(glyph.width);
        const index = y * row_stride + (x / 8);
        const bit: u3 = @intCast(x % 8);
        const mask: u8 = @as(u8, 1) << bit;

        switch (value) {
            .unset => glyph.bits[index] &= ~mask,
            .set => glyph.bits[index] |= mask,
        }
    }

    pub fn get_pixel(glyph: Glyph, x: usize, y: usize) Pixel {
        const row_stride = pixels_to_bytes(glyph.width);
        const index = y * row_stride + (x / 8);
        const bit: u3 = @intCast(x % 8);
        const mask: u8 = @as(u8, 1) << bit;

        return if (glyph.bits[index] & mask != 0)
            .set
        else
            .unset;
    }

    pub fn optimize(glyph: *Glyph) void {
        var min_x: usize = std.math.maxInt(usize);
        var max_x: usize = 0;
        var min_y: usize = std.math.maxInt(usize);
        var max_y: usize = 0;

        for (0..glyph.height) |y| {
            for (0..glyph.width) |x| {
                switch (glyph.get_pixel(x, y)) {
                    .unset => {},
                    .set => {
                        min_x = @min(min_x, x);
                        max_x = @max(max_x, x + 1);
                        min_y = @min(min_y, y);
                        max_y = @max(max_y, y + 1);
                    },
                }
            }
        }

        const new_width = max_x -| min_x;
        const new_height = max_y -| min_y;

        const dx = @min(glyph.width, min_x);
        const dy = @min(glyph.height, min_y);

        //
        // Adjust pixel data in three steps:
        // 1. Shift all pixels up/left
        // 2. Compact the image to the new stride
        // 3. Trim the memory length
        //
        // This way, we don't overwrite any pixels in the bitmap.
        // Stride adjustment must be done last, as otherwise, we'd
        // have overlapping segments of new and old pixels.
        //

        // 1. Shift the pixels
        for (0..new_height) |y| {
            for (0..new_width) |x| {
                const pixel = glyph.get_pixel(x + dx, y + dy);
                glyph.set_pixel(x, y, pixel);
            }
        }

        // 2. Compact to the new stride
        // We can always skip the first row, as it's always 0 => 0
        const old_row_stride = pixels_to_bytes(glyph.width);
        const new_row_stride = pixels_to_bytes(new_width);
        std.debug.assert(old_row_stride >= new_row_stride);

        if (old_row_stride > new_row_stride) {
            // we only need to compact if the stride
            // actually changed. otherwise, the data layout
            // is already correct.
            var old: usize = 0;
            var new: usize = 0;
            for (0..new_height) |_| {
                std.mem.copyForwards(
                    u8,
                    glyph.bits[new..][0..new_row_stride],
                    glyph.bits[old..][0..new_row_stride],
                );

                old += old_row_stride;
                new += new_row_stride;
            }
            std.debug.assert(new <= glyph.bits.len);
            std.debug.assert(old <= glyph.bits.len);
        }

        std.debug.assert(glyph.bits.len >= new_row_stride * new_height);

        // Update the current glyph to the new values
        glyph.width = @intCast(new_width);
        glyph.height = @intCast(new_height);
        glyph.offset_x += @intCast(dx);
        glyph.offset_y += @intCast(dy);
        glyph.bits.len = new_row_stride * new_height;
    }

    pub fn dump(glyph: Glyph, prefix: []const u8) void {
        std.debug.print("{s}: {}x{} +({},{}), +={}\n", .{
            prefix,
            glyph.width,
            glyph.height,
            glyph.offset_x,
            glyph.offset_y,
            glyph.advance,
        });

        std.debug.print("{s}.", .{prefix});
        for (0..glyph.width) |_| {
            std.debug.print("-", .{});
        }
        std.debug.print(".\n", .{});

        for (0..glyph.height) |y| {
            std.debug.print("{s}|", .{prefix});

            for (0..glyph.width) |x| {
                std.debug.print("{s}", .{switch (glyph.get_pixel(x, y)) {
                    .unset => " ",
                    .set => "X",
                }});
            }
            std.debug.print("|\n", .{});
        }

        std.debug.print("{s}'", .{prefix});
        for (0..glyph.width) |_| {
            std.debug.print("-", .{});
        }
        std.debug.print("'\n", .{});
    }
};

pub const Builder = struct {
    arena: std.heap.ArenaAllocator,
    glyphs: std.AutoArrayHashMapUnmanaged(u21, *Glyph) = .empty,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{
            .arena = .init(allocator),
        };
    }

    pub fn deinit(builder: *Builder) void {
        builder.arena.deinit();
        builder.* = undefined;
    }

    pub fn add(builder: *Builder, codepoint: u21, options: struct {
        advance: u8,
        width: usize,
        height: usize,
        offset_x: i8,
        offset_y: i8,
    }) !*Glyph {
        const width8 = std.math.cast(u8, options.width) orelse return error.Dimension;
        const height8 = std.math.cast(u8, options.height) orelse return error.Dimension;

        const arena = builder.arena.allocator();

        const row_stride = pixels_to_bytes(options.width);
        const byte_size = row_stride * options.height;

        const kvp = try builder.glyphs.getOrPut(arena, codepoint);
        if (kvp.found_existing)
            return error.DuplicateKey;

        const glyph = try arena.create(Glyph);
        defer arena.destroy(glyph);

        const bits = try arena.alloc(u8, byte_size);
        @memset(bits, 0);

        glyph.* = .{
            .advance = options.advance,
            .width = width8,
            .height = height8,
            .offset_x = options.offset_x,
            .offset_y = options.offset_y,
            .bits = bits,
        };

        kvp.value_ptr.* = glyph;

        return glyph;
    }
};

pub fn render(
    file: std.fs.File,
    font: Builder,
    info: FontInfo,
) !void {
    const writer = file.writer();

    // Write file header:
    try writer.writeInt(u32, 0xcb3765be, .little);
    try writer.writeInt(u32, info.line_height, .little);
    try writer.writeInt(u32, @intCast(font.glyphs.count()), .little);

    // Write `glyph_meta` array:
    for (font.glyphs.keys(), font.glyphs.values()) |codepoint, glyph| {
        const Meta = packed struct(u32) {
            codepoint: u24,
            advance: u8,
        };
        const meta: Meta = .{
            .codepoint = codepoint,
            .advance = glyph.advance,
        };
        const meta_value: u32 = @bitCast(meta);

        try writer.writeInt(u32, meta_value, .little);
    }

    // var glyph_sizes: std.AutoArrayHashMap(u21, struct { u32, usize }) = .init(allocator);
    // defer glyph_sizes.deinit();

    // Write `glyph_offsets` array:
    {
        var base_offset: u32 = 0;
        for (font.glyphs.keys()) |codepoint| {
            const glyph_bitmap = font.glyphs.get(codepoint).?;
            std.debug.assert(glyph_bitmap.bits.len == glyph_bitmap.height * pixels_to_bytes(glyph_bitmap.width));

            const encoded_glyph_size: u32 = @intCast(4 + glyph_bitmap.bits.len);

            try writer.writeInt(u32, base_offset, .little);

            // try glyph_sizes.put(codepoint, .{ base_offset, encoded_glyph_size });

            base_offset += encoded_glyph_size;
        }
    }

    // Write `glyphs` data array:
    {
        // const start = try writer.context.getPos();
        for (font.glyphs.keys()) |codepoint| {
            // const expected_offset, const expected_size = glyph_sizes.get(codepoint).?;
            const glyph_bitmap = font.glyphs.get(codepoint).?;

            // const offset = try writer.context.getPos();
            // std.debug.assert(offset - start == expected_offset);

            try writer.writeInt(u8, glyph_bitmap.width, .little);
            try writer.writeInt(u8, glyph_bitmap.height, .little);
            try writer.writeInt(i8, glyph_bitmap.offset_x, .little);
            try writer.writeInt(i8, glyph_bitmap.offset_y, .little);
            try writer.writeAll(glyph_bitmap.bits);

            // const end = try writer.context.getPos();
            // std.debug.assert(end - offset == expected_size);
        }
    }
}

pub fn pixels_to_bytes(bits: usize) usize {
    return (bits + 7) / 8;
}
