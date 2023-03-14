const std = @import("std");
const hypertext = @import("hypertext");
const hyperdoc = @import("hyperdoc");
const args = @import("args");
const ashet = @import("ashet");
const gui = @import("ashet-gui");
const zigimg = @import("zigimg");

const ColorIndex = ashet.abi.ColorIndex;
const color_black = ColorIndex.get(0x00);
const color_white = ColorIndex.get(0x0F);

const wikitheme = hypertext.Theme{
    .text_color = ColorIndex.get(0x00), // black
    .monospace_color = ColorIndex.get(0x0D), // pink
    .emphasis_color = ColorIndex.get(0x03), // dark red
    .link_color = ColorIndex.get(0x02), // blue

    .h1_color = ColorIndex.get(0x03), // dark red
    .h2_color = ColorIndex.get(0x00), // black
    .h3_color = ColorIndex.get(0x11), // dim gray

    .quote_mark_color = ColorIndex.get(0x05), // dark green

    .padding = 4,

    .line_spacing = 2,
    .block_spacing = 6,
};

const loadPaletteFile = @import("lib/palette.zig").loadPaletteFile;

const CliOptions = struct {
    output: ?[]const u8 = null,
    palette: ?[]const u8 = null,

    pub const shorthands = .{
        .o = "output",
        .p = "palette",
    };
};

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var cli = args.parseForCurrentProcess(CliOptions, allocator, .print) catch return 1;
    defer cli.deinit();

    const palette_file_name = cli.options.palette orelse "./src/kernel/data/palette.gpl";
    const output_file_name = cli.options.output orelse @panic("missing output file name");
    const input_file_name = if (cli.positionals.len == 1)
        cli.positionals[0]
    else
        @panic("expects exactly one argument!");

    const palette = try loadPaletteFile(allocator, palette_file_name);
    defer allocator.free(palette);

    var document = blk: {
        var file_text = try std.fs.cwd().readFileAlloc(allocator, input_file_name, 10 << 20);
        defer allocator.free(file_text);

        break :blk try hyperdoc.parse(allocator, file_text);
    };
    defer document.deinit();

    const width = 320;
    const height = 640;

    var target_image_buffer: [height][width]ashet.abi.ColorIndex = undefined;
    {
        var fb = gui.Framebuffer{
            .width = width,
            .height = height,
            .stride = width,
            .pixels = &target_image_buffer[0],
        };
        fb.clear(color_white);

        hypertext.renderDocument(
            fb,
            document,
            wikitheme,
            0,
        );

        // TODO: Render data here
    }

    {
        var output_image = try zigimg.Image.create(allocator, width, height, .rgba32);
        defer output_image.deinit();

        for (output_image.pixels.rgba32, 0..) |*dest, index| {
            const color_id = @ptrCast(*const [width * height]u8, &target_image_buffer)[index];
            dest.* = palette[color_id];
        }

        try output_image.writeToFilePath(output_file_name, .{
            .png = .{ .interlaced = false },
        });
    }

    return 0;
}
