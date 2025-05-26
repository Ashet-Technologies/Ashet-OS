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

    const design_size = document.window.design_size;

    for (document.window.widgets.items) |widget| {
        const anchor = widget.anchor;
        const name: []const u8 = widget.identifier.items;

        const v_align: Align = .from_anchor(anchor.top, anchor.bottom);
        const h_align: Align = .from_anchor(anchor.left, anchor.right);

        try writer.writeAll("    {\n");
        try writer.print("        const x: i16 = {};\n", .{h_align.format_pos(widget.bounds.x, widget.bounds.width, design_size.width)});
        try writer.print("        const y: i16 = {};\n", .{v_align.format_pos(widget.bounds.y, widget.bounds.height, design_size.height)});
        try writer.print("        const width: u16 = {};\n", .{h_align.format_size(widget.bounds.x, widget.bounds.width, design_size.width)});
        try writer.print("        const height: u16 = {};\n", .{v_align.format_size(widget.bounds.y, widget.bounds.height, design_size.height)});

        try writer.print("        try target.draw_widget(.{{ .x = x, .y = y, .width = width, .height = height }}, .{}, ", .{
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

const Align = enum {
    near,
    far,
    center,
    margin,

    fn from_anchor(near: bool, far: bool) Align {
        if (near) {
            return if (far) .margin else .near;
        } else {
            return if (far) .far else .center;
        }
    }

    fn format_pos(alignment: Align, pos: i16, size: u16, limit: u16) PosFormatter {
        return .{
            .alignment = alignment,
            .pos = pos,
            .size = size,
            .limit = limit,
        };
    }

    fn format_size(alignment: Align, pos: i16, size: u16, limit: u16) SizeFormatter {
        return .{
            .alignment = alignment,
            .pos = pos,
            .size = size,
            .limit = limit,
        };
    }

    const PosFormatter = struct {
        alignment: Align,
        pos: i16,
        size: u16,
        limit: u16,

        pub fn format(formatter: PosFormatter, fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = opt;
            switch (formatter.alignment) {
                .near, .margin => try writer.print("{}", .{formatter.pos}),
                .far => {
                    const margin = @as(i32, formatter.limit) - formatter.pos - formatter.size;

                    try writer.print("frame.width -| {}", .{formatter.size + margin});
                },
                .center => @panic("center"),
            }
        }
    };

    const SizeFormatter = struct {
        alignment: Align,
        pos: i16,
        size: u16,
        limit: u16,

        pub fn format(formatter: SizeFormatter, fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = opt;
            switch (formatter.alignment) {
                .near, .far => try writer.print("{}", .{formatter.size}),
                .margin => {
                    const margin = @as(i32, formatter.pos) + formatter.limit - formatter.pos - formatter.size;

                    try writer.print("frame.width -| {}", .{margin});
                },
                .center => @panic("center"),
            }
        }
    };
};
