const std = @import("std");
const args = @import("args");
const demosuite = @import("agp-demosuite");

const Options = struct {
    output: ?[]const u8 = null,
    size: Geometry = .{ .width = 320, .height = 200 },

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
    _ = input;

    var context = demosuite.create_context(allocator);
    defer context.deinit();

    var framebuffer = try context.create_framebuffer(
        cli.options.size.width,
        cli.options.size.height,
    );
    defer framebuffer.deinit();

    try framebuffer.encoder().clear(.white);
    try framebuffer.write_to(std.fs.cwd(), output);

    return 0;
}
