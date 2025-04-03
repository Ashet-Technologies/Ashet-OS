const std = @import("std");

const zgui = @import("zgui");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const args_parser = @import("args");

const model = @import("model.zig");

const Widget = model.Widget;
const Window = model.Window;
const Document = model.Document;

pub const CliOptions = struct {
    help: bool = false,

    pub const shorthands = .{
        .h = "help",
    };
};

fn usage_fault(comptime fmt: []const u8, params: anytype) !noreturn {
    const stderr = std.io.getStdErr();
    try stderr.writer().print("gui-compiler: " ++ fmt, params);
    std.process.exit(1);
}

pub fn main() !u8 {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var cli = args_parser.parseForCurrentProcess(CliOptions, allocator, .print) catch return 1;
    defer cli.deinit();

    const metadata = try model.load_metadata(allocator, @embedFile("widget-classes.json"));
    defer metadata.deinit();

    var document: Document = .{
        .allocator = allocator,
        .window = .{},
    };
    defer document.deinit();

    if (cli.positionals.len != 1) try usage_fault(
        "expects a single positional file, but {} were provided",
        .{cli.positionals.len},
    );

    {
        const file = try std.fs.cwd().openFile(cli.positionals[0], .{});
        defer file.close();

        document = try model.load_design(file.reader(), document.allocator, metadata);
    }

    try render_to_file(document, std.io.getStdOut());

    return 0;
}

pub fn render_to_file(document: Document, stream: std.fs.File) !void {
    var buffered_writer = std.io.bufferedWriter(stream.writer());
    const writer = buffered_writer.writer();

    try writer.writeAll(
        \\// This is auto-generated code!
        \\const std = @import("std");
        \\const ashet = @import("ashet");
        \\
        \\const Layout = @This();
        \\
        \\pub fn render(layout: Layout, frame: ashet.Rectangle, target: anytype) !void {
        \\
    );

    for (document.window.widgets.items) |widget| {
        const name: []const u8 = widget.identifier.items;
        try writer.writeAll("    {\n");
        try writer.writeAll("        const bounds: ashet.Rectangle = .{\n");
        try writer.writeAll("            .x = ,\n");
        try writer.writeAll("            .y = ,\n");
        try writer.writeAll("            .width = ,\n");
        try writer.writeAll("            .height = ,\n");
        try writer.writeAll("        };\n");

        try writer.print("        try target.draw_widget(bounds, .{}, ", .{
            std.zig.fmtId(widget.class.name),
        });

        if (name.len > 0) {
            try writer.print("layout.{}", .{
                std.zig.fmtId(name),
            });
        } else {
            //
            try writer.writeAll("null");
        }
        try writer.writeAll(");\n");
        try writer.writeAll("    }\n");
    }

    try writer.writeAll(
        \\}
        \\
    );

    try buffered_writer.flush();
}
