const std = @import("std");
const ashet = @import("ashet");
const turtlefont = @import("turtlefont");

const Point = ashet.abi.Point;
const Size = ashet.abi.Size;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;

pub const Font = union(enum) {
    bitmap: BitmapFont,
    vector: VectorFont,

    pub fn load(buffer: []const u8, size_hint: ?u15) error{InvalidFont}!Font {
        if (BitmapFont.load(buffer)) |bmp| {
            return Font{ .bitmap = bmp };
        } else |_| if (VectorFont.load(buffer, size_hint orelse 8)) |vec| {
            return Font{ .vector = vec };
        } else |e| {
            return e;
        }
    }

    pub fn lineHeight(font: Font) u15 {
        return switch (font) {
            .bitmap => |bmp| bmp.lineHeight(),
            .vector => |vec| vec.size,
        };
    }

    pub const default: Font = blk: {
        @setEvalBranchQuota(10_000);
        break :blk Font.load(@embedFile("fonts/mono.font"), 8) catch |err| @compileError("failed to embed default font: " ++ @errorName(err));
    };
};

pub const BitmapFont = struct {
    const magic_number = 0xcb3765be;

    /// Data encoding:
    /// ```
    /// struct {
    ///   font_id: u32 = 0xcb3765be,
    ///   line_height: u32,
    ///   glyph_count: u32,
    ///   glyph_meta: [glyph_count] packed struct (u32) {
    ///         codepoint: u24,
    ///         advance: u8,
    ///   },
    ///   glpyh_offsets: [glyph_count] u32,
    ///   glyphs: [*]u8,
    ///
    ///   // encoded as:
    ///   // struct {
    ///   //    width: u8, // 255 must be enough for everyone
    ///   //    height: u8,  // 255 must be enough for everyone
    ///   //    offset_x: i8, // offset of the glyph to the base point
    ///   //    offset_y: i8, // offset of the glyph to the base point
    ///   //    bits: [(height+7)/8 * width]u8, // column-major bitmap
    ///   // }
    /// }
    /// ```
    ///
    data: []const u8,

    const PackedCodepointAdvance = packed struct(u32) {
        codepoint: u24,
        advance: u8,
    };

    fn glyphCount(bf: BitmapFont) u32 {
        return std.mem.readIntLittle(u32, bf.data[8..12]);
    }

    fn lineHeight(bf: BitmapFont) u32 {
        return std.mem.readIntLittle(u32, bf.data[4..8]);
    }

    fn getGlyphMeta(bf: BitmapFont, index: usize) PackedCodepointAdvance {
        return @bitCast(PackedCodepointAdvance, std.mem.readIntLittle(u32, bf.data[12 + 4 * index ..][0..4]));
    }

    fn getGlyphOffset(bf: BitmapFont, index: usize) u32 {
        const count = bf.glyphCount();
        return std.mem.readIntLittle(u32, bf.data[12 + 4 * count + 4 * index ..][0..4]);
    }

    fn getEncodedGlyphs(bf: BitmapFont) []const u8 {
        const count = bf.glyphCount();
        return bf.data[12 + 8 * count ..];
    }

    pub fn load(buffer: []const u8) !BitmapFont {
        if (buffer.len < 12)
            return error.InvalidFont;

        const magic = std.mem.readIntLittle(u32, buffer[0..4]);
        if (magic != magic_number)
            return error.InvalidFont;

        var font = BitmapFont{ .data = buffer };

        const count = font.glyphCount();

        const glyph_storage = font.getEncodedGlyphs();

        var previous_codepoint: i32 = -1;

        for (0..count) |i| {
            const meta = font.getGlyphMeta(i);
            const offset = font.getGlyphOffset(i);

            if (meta.codepoint <= previous_codepoint)
                return error.InvalidFont;
            previous_codepoint = meta.codepoint;

            if (meta.codepoint > std.math.maxInt(u21))
                return error.InvalidFont;
            if (offset > glyph_storage.len + 4)
                return error.InvalidFont;

            const encoded_glyph = glyph_storage[offset..];

            const width = std.mem.readIntLittle(u8, encoded_glyph[0..1]);
            const height = std.mem.readIntLittle(u8, encoded_glyph[1..2]);
            const stride = (height + 7) / 8;
            const size = width * stride;

            if (encoded_glyph.len < 4 + size)
                return error.InvalidFont;
        }

        return font;
    }

    pub const Glyph = struct {
        advance: u8,
        width: u8, // 255 must be enough for everyone
        height: u8, // 255 must be enough for everyone
        offset_x: i8, // offset of the glyph to the base point
        offset_y: i8, // offset of the glyph to the base point
        bits: []const u8, // column-major bitmap ((height+7)/8 * width)
    };

    pub fn getGlyphIndex(font: BitmapFont, codepoint: u21) ?usize {
        const total_count = font.glyphCount();

        var base: usize = 0;
        var count: usize = total_count;

        while (count > 0) {
            const pivot = base + count / 2;

            const meta = font.getGlyphMeta(pivot);

            if (meta.codepoint == codepoint) {
                return pivot;
            }

            if (meta.codepoint < codepoint) {
                base += (count + 1) / 2;
                count = count / 2;
            } else {
                count /= 2;
            }
        }
        return null;
    }

    pub fn getGlyph(font: BitmapFont, codepoint: u21) ?Glyph {
        const index = font.getGlyphIndex(codepoint) orelse return null;

        const meta = font.getGlyphMeta(index);

        const offset = font.getGlyphOffset(index);

        const encoded_glyph = font.getEncodedGlyphs()[offset..];

        const width = std.mem.readIntLittle(u8, encoded_glyph[0..1]);
        const height = std.mem.readIntLittle(u8, encoded_glyph[1..2]);
        const stride = (height + 7) / 8;
        const size = width * stride;

        return Glyph{
            .advance = meta.advance,

            .width = width,
            .height = height,
            .offset_x = std.mem.readIntLittle(i8, encoded_glyph[2..3]),
            .offset_y = std.mem.readIntLittle(i8, encoded_glyph[3..4]),

            .bits = encoded_glyph[4 .. 4 + size],
        };
    }
};

pub const VectorFont = struct {
    turtle_font: turtlefont.Font,
    size: u15,

    pub fn load(buffer: []const u8, size: u15) !VectorFont {
        const font = try turtlefont.Font.load(buffer);
        return VectorFont{
            .turtle_font = font,
            .size = size,
        };
    }
};
