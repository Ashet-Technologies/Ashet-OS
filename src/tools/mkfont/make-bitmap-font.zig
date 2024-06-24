// clear && zig run tools/make-bitmap-font.zig  --main-pkg-path . > rootfs/system/fonts/mono.font && hexdump -C rootfs/system/fonts/mono.font

const std = @import("std");

pub fn main() !void {
    var output = std.io.getStdOut();

    const writer = output.writer();

    try writer.writeInt(u32, 0xcb3765be, .little);
    try writer.writeInt(u32, 8, .little);
    try writer.writeInt(u32, 256, .little);

    for (0..256) |cp| {
        try writer.writeInt(u32, @as(u32, @intCast(cp)) | (6 << 24), .little);
    }

    for (0..256) |i| {
        try writer.writeInt(u32, @intCast(10 * i), .little);
    }

    const src_w = 7;
    const src_h = 9;

    const src_dx = 1;
    const src_dy = 1;

    const dst_w = 6;
    const dst_h = 8;

    const source_pixels = @embedFile("raw_font");
    if (source_pixels.len != src_w * src_h * 256)
        @compileError(std.fmt.comptimePrint("Font file must be 16 by 16 characters of size {}x{}", .{ src_w, src_h }));

    if (dst_h > 8)
        @compileError("dst_h must be less than 9!");

    var c: usize = 0;
    while (c < 256) : (c += 1) {
        const cx = c % 16;
        const cy = c / 16;

        try writer.writeInt(u8, 6, .little); // glyph width
        try writer.writeInt(u8, 8, .little); // glyph height
        try writer.writeInt(i8, 0, .little); // offset x
        try writer.writeInt(i8, 0, .little); // offset y

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
                    bits |= @as(u8, 1) << @intCast(y);
                }
            }

            try writer.writeInt(u8, bits, .little);
        }
    }
}
