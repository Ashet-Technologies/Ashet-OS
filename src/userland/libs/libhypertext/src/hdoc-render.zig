const std = @import("std");
const args = @import("args");
const demosuite = @import("agp-demosuite");
const hypertext = @import("hypertext");
const hdoc = @import("hyperdoc");

const Options = struct {
    output: ?[]const u8 = null,
    size: Geometry = .{ .width = 640, .height = 400 },

    pub const shorthands = .{
        .o = "output",
        .s = "size",
    };
};

const Geometry = struct {
    width: u16,
    height: u16,

    pub fn parse(str: []const u8) !Geometry {
        const split = std.mem.indexOfScalar(u8, str, 'x') orelse return error.InvalidValue;

        const head = str[0..split];
        const tail = str[split + 1 ..];

        const width = try std.fmt.parseInt(u16, head, 10);
        const height = try std.fmt.parseInt(u16, tail, 10);

        return .{ .width = width, .height = height };
    }
};

const max_input_bytes = 10 * 1024 * 1024;

pub fn main() !u8 {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var cli = args.parseForCurrentProcess(Options, allocator, .print) catch return 1;
    defer cli.deinit();

    if (cli.options.size.width <= 0 or cli.options.size.height <= 0) {
        std.log.err("Size must be a non-empty area, found {}x{}", .{
            cli.options.size.width, cli.options.size.height,
        });
        return 1;
    }

    const output = cli.options.output orelse {
        std.log.err("pass -o or --output with a GIF file path", .{});
        return 1;
    };
    if (cli.positionals.len > 1) {
        std.log.err("expected at most one input file", .{});
        return 1;
    }

    const input_path = if (cli.positionals.len == 0) "-" else cli.positionals[0];
    const input: []const u8 = if (std.mem.eql(u8, input_path, "-"))
        try std.fs.File.stdin().readToEndAlloc(allocator, max_input_bytes)
    else
        try std.fs.cwd().readFileAlloc(allocator, input_path, max_input_bytes);

    var err_pos: hdoc.ErrorLocation = undefined;
    var document = hdoc.parse(
        allocator,
        input,
        &err_pos,
    ) catch |err| {
        std.log.err("{?s}:{}:{}: {t}", .{ err_pos.source, err_pos.line, err_pos.column, err });
        return 1;
    };
    defer document.deinit();

    var context = demosuite.create_context(allocator);
    defer context.deinit();

    const default_font = try context.load_font(@embedFile("fonts/sans.font"), .{
        .size = 16,
        .bold = false,
        .italic = false,
    });

    const monospace_font = try context.load_font(@embedFile("fonts/mono-8.font"), .{
        .size = 8,
        .bold = false,
        .italic = false,
    });

    var framebuffer = try context.create_framebuffer(
        cli.options.size.width,
        cli.options.size.height,
    );
    defer framebuffer.deinit();

    {
        var encoder = framebuffer.encoder();

        try encoder.clear(.red);
        try encoder.set_clip_rect(1, 1, framebuffer.width - 2, framebuffer.height - 2);
        try encoder.clear(.white);

        const ctx = hypertext.Context{
            .user_data = &context,
            .measure_text_size_fn = hypertext_measure_text_size,
        };

        const target: hypertext.Rectangle = .{
            .x = 10,
            .y = 10,
            .width = framebuffer.width - 20,
            .height = framebuffer.height - 20,
        };

        try encoder.fill_rect(
            target.x,
            target.y,
            target.width,
            target.height,
            .{ .hue = 5, .value = 7, .saturation = 1 },
        );

        try hypertext.render_document(
            &ctx,
            &encoder,
            &document,
            target,
            .{
                .default_font = default_font,
                .monospace_font = monospace_font,
            },
        );
    }

    try framebuffer.write_to(std.fs.cwd(), output);

    return 0;
}

fn hypertext_measure_text_size(user_data: ?*anyopaque, font: hypertext.Font, text: []const u8) hypertext.Size {
    const ctx: *demosuite.Context = @ptrCast(@alignCast(user_data.?));

    return ctx.measure_text_size(font, text) catch @panic("implementation bug");
}
