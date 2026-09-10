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

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    var cli = args_parser.parseForCurrentProcess(CliOptions, init, .print) catch return 1;
    defer cli.deinit();

    if (cli.positionals.len != 1) {
        @panic("requires a single positional argument!");
    }

    const input_file_name = cli.positionals[0];
    const output_file_name = cli.options.output orelse @panic("requires output file name");

    var input_file = try std.Io.Dir.cwd().openFile(io, input_file_name, .{});
    defer input_file.close(io);

    var buffer: [4096]u8 = undefined;
    var file_reader = input_file.reader(io, &buffer);
    const reader = &file_reader.interface;

    const magic = try reader.takeInt(u32, .little);
    if (magic != 0x48198b74) {
        @panic("invalid magic number!");
    }
    const width = try reader.takeInt(u16, .little);
    const height = try reader.takeInt(u16, .little);
    const flags = try reader.takeInt(u16, .little);
    const is_transparent = (flags & 1) != 0;
    const palette_size = try reader.takeInt(u8, .little);
    const transparency_key = try reader.takeInt(u8, .little);

    const indexed_bitmap = try arena.allocator().alloc(u8, @as(usize, width) * height);
    const palette = try arena.allocator().alloc(Rgba32, palette_size);

    try reader.readSliceAll(indexed_bitmap);

    for (palette) |*color| {
        const packed_color = try reader.takeInt(u16, .little);

        const color_565 = @as(packed struct(u16) { r: u5, g: u6, b: u5 }, @bitCast(packed_color));

        color.* = Rgba32.from.u32Rgba(
            zigimg.color.Rgb565.from.rgb(
                color_565.r,
                color_565.g,
                color_565.b,
            ).to.u32Rgba(),
        );
    }

    var output_image = try zigimg.Image.create(
        arena.allocator(),
        width,
        height,
        .rgba32,
    );
    defer output_image.deinit(arena.allocator());

    for (output_image.pixels.rgba32, 0..) |*dest, index| {
        const color_id = indexed_bitmap[index];
        if (is_transparent and (color_id == transparency_key))
            dest.* = Rgba32.from.rgba(0, 0, 0, 0)
        else
            dest.* = palette[color_id];
    }

    var write_buffer: [4096]u8 = undefined;
    try output_image.writeToFilePath(arena.allocator(), io, output_file_name, &write_buffer, .{
        .png = .{ .interlaced = false },
    });

    return 0;
}
