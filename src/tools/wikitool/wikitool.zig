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

const font = &gui.Font.default;

const wikitheme = hypertext.Theme{
    .text = .{ .font = font, .color = ColorIndex.get(0x00) }, // black
    .monospace = .{ .font = font, .color = ColorIndex.get(0x0D) }, // pink
    .emphasis = .{ .font = font, .color = ColorIndex.get(0x03) }, // dark red
    .link = .{ .font = font, .color = ColorIndex.get(0x02) }, // blue

    .h1 = .{ .font = font, .color = ColorIndex.get(0x03) }, // dark red
    .h2 = .{ .font = font, .color = ColorIndex.get(0x00) }, // black
    .h3 = .{ .font = font, .color = ColorIndex.get(0x11) }, // dim gray

    .quote_mark_color = ColorIndex.get(0x05), // dark green

    .padding = 4,

    .line_spacing = 2,
    .block_spacing = 4,
};

const loadPaletteFile = @import("lib/palette.zig").loadPaletteFile;

const CliOptions = struct {
    output: ?[]const u8 = null,
    palette: ?[]const u8 = null,
    scroll: u15 = 0,

    pub const shorthands = .{
        .o = "output",
        .p = "palette",
        .s = "scroll",
    };
};

fn emitSensitiveRectangle(fb: *gui.Framebuffer, rect: ashet.abi.Rectangle, link: hyperdoc.Link) void {
    std.log.info("Rectangle: {} => '{s}'", .{
        rect,
        link.href,
    });
    // fb.drawRectangle(rect.grow(1), ColorIndex.get(0x0E));
    _ = fb;
}

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
        const file_text = try std.fs.cwd().readFileAlloc(allocator, input_file_name, 10 << 20);
        defer allocator.free(file_text);

        var error_pos: hyperdoc.ErrorLocation = undefined;

        break :blk hyperdoc.parse(allocator, file_text, &error_pos) catch |err| {
            std.log.err("failed to parse {s}:{}:{}: {s}", .{
                input_file_name,
                error_pos.line,
                error_pos.column,
                @errorName(err),
            });
            return 1;
        };
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
            gui.Point.new(0, -@as(i16, cli.options.scroll)),
            &fb,
            emitSensitiveRectangle,
        );

        // TODO: Render data here
    }

    {
        var output_image = try zigimg.Image.create(allocator, width, height, .rgba32);
        defer output_image.deinit();

        const target_buffer: *const [width * height]u8 = @ptrCast(&target_image_buffer);

        for (output_image.pixels.rgba32, 0..) |*dest, index| {
            const color_id = target_buffer[index];
            dest.* = palette[color_id];
        }

        try output_image.writeToFilePath(output_file_name, .{
            .png = .{ .interlaced = false },
        });
    }

    return 0;
}
