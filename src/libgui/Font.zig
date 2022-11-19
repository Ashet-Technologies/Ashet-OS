const std = @import("std");
const ashet = @import("ashet");

const Point = ashet.abi.Point;
const Size = ashet.abi.Size;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;

pub const Font = @This();

pub const Glyph = struct {
    bits: [6]u8,
};

glyph_size: Size,
glyphs: [256][6]u8,

pub fn getGlyph(font: Font, char: u21) Glyph {
    return Glyph{ .bits = font.glyphs[char] };
}

pub const default: Font = blk: {
    @setEvalBranchQuota(100_000);

    var data: [256][6]u8 = undefined;

    const src_w = 7;
    const src_h = 9;

    const src_dx = 1;
    const src_dy = 1;

    const dst_w = 6;
    const dst_h = 8;

    const source_pixels = @embedFile("fonts/6x8.raw");
    if (source_pixels.len != src_w * src_h * 256)
        @compileError(std.fmt.comptimePrint("Font file must be 16 by 16 characters of size {}x{}", .{ src_w, src_h }));

    if (dst_h > 8)
        @compileError("dst_h must be less than 9!");

    var c = 0;
    while (c < 256) : (c += 1) {
        const cx = c % 16;
        const cy = c / 16;

        var x = 0;
        while (x < dst_w) : (x += 1) {
            var bits = 0;

            var y = 0;
            while (y < dst_h) : (y += 1) {
                const src_x = src_dx + src_w * cx + x;
                const src_y = src_dy + src_h * cy + y;

                const src_i = 16 * src_w * src_y + src_x;

                const pix = source_pixels[src_i];

                if (pix != 0) {
                    bits |= (1 << y);
                }
            }

            data[c][x] = bits;
        }
    }

    break :blk Font{
        .glyphs = data,
        .glyph_size = Size.new(6, 8),
    };
};
