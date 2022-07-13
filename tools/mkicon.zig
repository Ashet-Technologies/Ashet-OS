const std = @import("std");
const zigimg = @import("zigimg");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    const args = try std.process.argsAlloc(arena.allocator());
    if (args.len != 3) {
        @panic("requires 2 args!");
    }

    std.log.info("processing {s}", .{args[1]});

    var raw_image = try zigimg.Image.fromFilePath(arena.allocator(), args[1]);

    if (raw_image.width != 64 or raw_image.height != 64)
        @panic("image must be 64x64");

    var reduced_img = try zigimg.Image.create(arena.allocator(), 64, 64, .rgb565, .raw);
    const reduced_pixels = reduced_img.pixels.?.rgb565;

    // convert to rgb565

    const transparent_pixel = zigimg.color.Rgb565{
        .r = 0x1F,
        .g = 0x00,
        .b = 0x1F,
    };

    {
        var src_pixels = raw_image.iterator();
        for (reduced_pixels) |*pixel| {
            const src_color: zigimg.color.Colorf32 = src_pixels.next() orelse unreachable;

            if (src_color.a > 0.5) {
                pixel.* = zigimg.color.Rgb565.fromU32Rgba(src_color.toU32Rgba());
            } else {
                pixel.* = transparent_pixel;
            }
        }
    }

    // compute palette

    var color_map = std.AutoArrayHashMap(zigimg.color.Rgb565, void).init(arena.allocator());

    try color_map.put(transparent_pixel, {});

    for (reduced_pixels) |pixel| {
        const gop = try color_map.getOrPut(pixel);
        if (gop.found_existing)
            continue;
    }

    const palette = color_map.keys();

    if (palette.len > 16) {
        for (palette) |color, index| {
            const rgb = zigimg.color.Rgb24.fromU32Rgb(color.toU32Rgb());
            std.log.info("{} => #{X:0>2}{X:0>2}{X:0>2}", .{ index, rgb.r, rgb.g, rgb.b });
        }
        std.debug.panic("source image has more than 15 different colors: {d}!", .{palette.len});
    }

    std.debug.assert(color_map.getIndex(transparent_pixel) orelse unreachable == 0);

    // compute bitmap

    var out_file = try std.fs.cwd().createFile(args[2], .{});
    defer out_file.close();

    var buffered_writer = std.io.bufferedWriter(out_file.writer());
    var writer = buffered_writer.writer();

    for (reduced_pixels) |pixel| {
        const index = @truncate(u8, color_map.getIndex(pixel) orelse unreachable);
        try writer.writeByte(index);
    }

    for (palette[1..]) |color| {
        try writer.writeIntLittle(u16, @bitCast(u16, color));
    }

    var i: usize = palette.len;
    while (i < 16) : (i += 1) {
        try writer.writeIntLittle(u16, 0xFFFF);
    }

    try buffered_writer.flush();
}
