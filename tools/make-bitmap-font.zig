// clear && zig run tools/make-bitmap-font.zig  --main-pkg-path . > rootfs/system/fonts/mono.font && hexdump -C rootfs/system/fonts/mono.font

const std = @import("std");

pub fn main() !void {
    var output = std.io.getStdOut();

    const writer = output.writer();

    try writer.writeIntLittle(u32, 0xcb3765be);
    try writer.writeIntLittle(u32, 8);
    try writer.writeIntLittle(u32, 256);

    for (0..256) |cp| {
        try writer.writeIntLittle(u32, @intCast(u32, cp) | (6 << 24));
    }

    for (0..256) |i| {
        try writer.writeIntLittle(u32, @intCast(u32, 10 * i));
    }

    const src_w = 7;
    const src_h = 9;

    const src_dx = 1;
    const src_dy = 1;

    const dst_w = 6;
    const dst_h = 8;

    const source_pixels = @embedFile("../src/libgui/fonts/6x8.raw");
    if (source_pixels.len != src_w * src_h * 256)
        @compileError(std.fmt.comptimePrint("Font file must be 16 by 16 characters of size {}x{}", .{ src_w, src_h }));

    if (dst_h > 8)
        @compileError("dst_h must be less than 9!");

    var c: usize = 0;
    while (c < 256) : (c += 1) {
        const cx = c % 16;
        const cy = c / 16;

        try writer.writeIntLittle(u8, 6); // glyph width
        try writer.writeIntLittle(u8, 8); // glyph height
        try writer.writeIntLittle(i8, 0); // offset x
        try writer.writeIntLittle(i8, 0); // offset y

        var x: usize = 0;
        while (x < dst_w) : (x += 1) {
            var bits: u8 = 0;

            var y: usize = 0;
            while (y < dst_h) : (y += 1) {
                const src_x = src_dx + src_w * cx + x;
                const src_y = src_dy + src_h * cy + y;

                const src_i = 16 * src_w * src_y + src_x;

                const pix = source_pixels[src_i];

                if (pix != 0) {
                    bits |= @as(u8, 1) << @intCast(u3, y);
                }
            }

            try writer.writeIntLittle(u8, bits);
        }
    }
}
