const std = @import("std");
const zigimg = @import("zigimg");
const abi = @import("ashet-abi");
const args_parser = @import("args");

const Rgba32 = zigimg.color.Rgba32;

const Palette = []Rgba32;

const CliOptions = struct {
    output: ?[]const u8 = null,

    pub const shorthands = .{
        .o = "output",
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

    var input_file = try std.fs.cwd().openFile(input_file_name, .{});
    defer input_file.close();

    var buffered_reader = std.io.bufferedReader(input_file.reader());
    var reader = buffered_reader.reader();

    const magic = try reader.readInt(u32, .little);
    if (magic != 0x48198b74) {
        @panic("invalid magic number!");
    }
    const width = try reader.readInt(u16, .little);
    const height = try reader.readInt(u16, .little);
    const flags = try reader.readInt(u16, .little);
    const is_transparent = (flags & 1) != 0;
    const palette_size = try reader.readInt(u8, .little);
    const transparency_key = try reader.readInt(u8, .little);

    const indexed_bitmap = try arena.allocator().alloc(u8, @as(usize, width) * height);
    const palette = try arena.allocator().alloc(Rgba32, palette_size);

    try reader.readNoEof(indexed_bitmap);

    for (palette) |*color| {
        const packed_color = try reader.readInt(u16, .little);

        const color_565 = abi.Color.fromU16(packed_color);

        color.* = Rgba32.fromU32Rgba(
            zigimg.color.Rgb565.initRgb(
                color_565.r,
                color_565.g,
                color_565.b,
            ).toU32Rgba(),
        );
    }

    var output_image = try zigimg.Image.create(
        arena.allocator(),
        width,
        height,
        .rgba32,
    );
    defer output_image.deinit();

    for (output_image.pixels.rgba32, 0..) |*dest, index| {
        const color_id = indexed_bitmap[index];
        if (is_transparent and (color_id == transparency_key))
            dest.* = Rgba32.initRgba(0, 0, 0, 0)
        else
            dest.* = palette[color_id];
    }

    try output_image.writeToFilePath(output_file_name, .{
        .png = .{ .interlaced = false },
    });

    return 0;
}
