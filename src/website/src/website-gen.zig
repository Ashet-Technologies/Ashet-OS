const std = @import("std");
const hdoc = @import("hyperdoc");
const abi_parser = @import("abi-mapper");

const templates = struct {
    const body = @embedFile("templates.body");
    const livedemo_head = @embedFile("templates.livedemo.head");
    const livedemo_body = @embedFile("templates.livedemo.body");
};

const wiki = @import("wiki-gen.zig");
const syscalls = @import("syscalls-gen.zig");

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);

    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);
    if (argv.len != 4)
        @panic("website-gen <output-dir> <wiki-src-dir> <abi-json-file>");

    var output_dir = try std.fs.cwd().makeOpenPath(argv[1], .{});
    defer output_dir.close();

    const wiki_root = argv[2];
    const abi_json_path = argv[3];

    var wiki_dir = try std.fs.cwd().openDir(wiki_root, .{ .iterate = true });
    defer wiki_dir.close();

    const abi_model = try load_abi_model(allocator, std.fs.cwd(), abi_json_path);
    defer abi_model.deinit();

    try render_root_page(output_dir);

    try render_live_demo(output_dir);

    try wiki.render(output_dir, wiki_dir, allocator);

    try syscalls.render(output_dir, abi_model.value, allocator);
}

fn load_abi_model(allocator: std.mem.Allocator, dir: std.fs.Dir, json_path: []const u8) !std.json.Parsed(abi_parser.model.Document) {
    const json_text = try dir.readFileAlloc(allocator, json_path, 2 * 1024 * 1024 * 1024);
    defer allocator.free(json_text);

    return try abi_parser.model.from_json_str(allocator, json_text);
}

pub fn render_root_page(output_dir: std.fs.Dir) !void {
    var reader = std.Io.Reader.fixed("<p>Hello, World!</p>");

    try render_page_file(output_dir, "index.html", &reader, .{
        .title = "Documentation",
    });
}

pub fn render_live_demo(output_dir: std.fs.Dir) !void {
    var head_reader = std.Io.Reader.fixed(templates.livedemo_head);
    var body_reader = std.Io.Reader.fixed(templates.livedemo_body);

    try render_page_file(output_dir, "livedemo/index.html", &body_reader, .{
        .title = "Live Demo",
        .header = &head_reader,
        .nesting = 1,
    });
}

pub const RenderOptions = struct {
    header: ?*std.Io.Reader = null,
    nesting: usize = 0,
    title: []const u8,
};

const Placeholder = enum {
    HEADER,
    MAIN,

    RELPATH,
    TITLE,

    fn is_singleton(p: Placeholder) bool {
        return switch (p) {
            .HEADER, .MAIN => true,

            .TITLE, .RELPATH => false,
        };
    }
};

pub fn render_page_file(output_dir: std.fs.Dir, path: []const u8, source: *std.Io.Reader, options: RenderOptions) !void {
    if (std.fs.path.dirname(path)) |parent_dir| {
        try output_dir.makePath(parent_dir);
    }

    var file = try output_dir.createFile(path, .{});
    defer file.close();

    var write_buffer: [4096]u8 = undefined;
    var writer = file.writer(&write_buffer);

    try render_page(&writer.interface, source, options);

    try writer.interface.flush();
}

pub fn render_page(target: *std.Io.Writer, source: *std.Io.Reader, options: RenderOptions) !void {
    const template = templates.body;

    var seen_tags: std.enums.EnumSet(Placeholder) = .initEmpty();

    var pos: usize = 0;
    while (pos < template.len) {
        if (std.mem.indexOfPos(u8, template, pos, "[[")) |next_placeholder_start| {
            if (next_placeholder_start > pos) {
                try target.writeAll(template[pos..next_placeholder_start]);
            }

            const next_placeholder_end = std.mem.indexOfPos(u8, template, next_placeholder_start, "]]") orelse @panic("invalid template!");

            const placeholder_id = template[next_placeholder_start + 2 .. next_placeholder_end];

            const placeholder = std.meta.stringToEnum(Placeholder, placeholder_id) orelse std.debug.panic("invalid placeholder: {s}", .{placeholder_id});

            if (placeholder.is_singleton() and seen_tags.contains(placeholder))
                @panic("invalid template: placeholder used twice!");
            seen_tags.insert(placeholder);

            switch (placeholder) {
                .HEADER => if (options.header) |header| {
                    _ = try header.streamRemaining(target);
                },
                .MAIN => _ = try source.streamRemaining(target),

                .RELPATH => {
                    try target.splatBytesAll("../", options.nesting);
                },
                .TITLE => try target.writeAll(options.title),
            }

            pos = next_placeholder_end + 2;
        } else {
            try target.writeAll(template[pos..]);
            pos = template.len;
        }
    }

    try target.flush();
}

pub fn fmt_html(str: []const u8) std.fmt.Formatter([]const u8, format_html_escape) {
    return .{ .data = str };
}

fn format_html_escape(str: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.writeAll(str); // TODO: Implement proper escaping
}

pub fn fmt_attr(str: []const u8) std.fmt.Formatter([]const u8, format_attr_escape) {
    return .{ .data = str };
}

fn format_attr_escape(str: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.writeAll(str); // TODO: Implement proper escaping
}

pub fn fmt_url(url: []const u8, nesting: usize) std.fmt.Formatter(struct { []const u8, usize }, format_url) {
    return .{ .data = .{ url, nesting } };
}

fn format_url(options: struct { []const u8, usize }, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    const url, const nesting = options;

    // TODO: Implement proper URL parsing and escaping

    if (std.mem.indexOf(u8, url, "://") != null) {
        // absolute url
        try writer.writeAll(url);
    } else {
        // relative url
        try writer.splatBytesAll("../", nesting);
        try writer.writeAll(url);
    }
}
