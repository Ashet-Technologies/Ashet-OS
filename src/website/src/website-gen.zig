const std = @import("std");
const hdoc = @import("hyperdoc");

const templates = struct {
    const body = @embedFile("templates.body");
    const livedemo_head = @embedFile("templates.livedemo.head");
    const livedemo_body = @embedFile("templates.livedemo.body");
};

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);

    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);

    var output_dir = try std.fs.cwd().makeOpenPath(argv[1], .{});
    defer output_dir.close();

    const wiki_root = argv[2];

    var wiki_dir = try std.fs.cwd().openDir(wiki_root, .{ .iterate = true });
    defer wiki_dir.close();

    try render_root_page(output_dir);

    try render_live_demo(output_dir);

    try wiki.render(output_dir, wiki_dir, allocator);
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

const wiki = struct {
    const Config = struct {
        allocator: std.mem.Allocator,
        base_nesting: usize,
        root: Folder,
    };

    const Folder = struct {
        files: []Item,
        nesting: usize,

        pub const Item = struct {
            path: []const u8,
            content: Content,
        };

        pub const Content = union(enum) {
            folder: Folder,
            document: Document,
            copy,
        };
    };

    const Document = struct {
        nesting: usize,
        output_path: []const u8,
        title: []const u8,
        contents: hdoc.Document,
    };

    fn render(output_dir: std.fs.Dir, wiki_src_dir: std.fs.Dir, allocator: std.mem.Allocator) !void {
        const root = try scan_folder(allocator, ".", wiki_src_dir, 0);

        var wiki_dst_dir = try output_dir.makeOpenPath("wiki", .{});
        defer wiki_dst_dir.close();

        try render_folder(.{
            .allocator = allocator,
            .base_nesting = 1,
            .root = root,
        }, wiki_src_dir, wiki_dst_dir, root);
    }

    fn render_folder(config: Config, input: std.fs.Dir, output: std.fs.Dir, folder: Folder) !void {
        for (folder.files) |entry| {
            switch (entry.content) {
                .folder => |subfolder| {
                    try output.makeDir(entry.path);
                    try render_folder(config, input, output, subfolder);
                },

                .copy => try std.fs.Dir.copyFile(
                    input,
                    entry.path,
                    output,
                    entry.path,
                    .{},
                ),

                .document => |document| {
                    var output_file = try output.createFile(document.output_path, .{ .exclusive = true });
                    defer output_file.close();

                    var buffer: [8192]u8 = undefined;
                    var file_writer = output_file.writer(&buffer);

                    try render_html(config, document, &file_writer.interface);

                    try file_writer.interface.flush();
                },
            }
        }
    }

    fn render_html(config: Config, doc: Document, writer: *std.Io.Writer) !void {
        var wiki_page: std.Io.Writer.Allocating = .init(config.allocator);
        defer wiki_page.deinit();

        const wiki_writer = &wiki_page.writer;

        try wiki_writer.writeAll(
            \\<main id="wiki">
            \\  <nav class="panel">
            \\    <ul class="treeview">
        );

        try render_toc(.{
            .allocator = config.allocator,
            .base_nesting = doc.nesting,
            .root = config.root,
        }, wiki_writer, config.root);

        try wiki_writer.writeAll(
            \\  </ul>
            \\</nav>
            \\<article class="panel markup-container">
        );

        try hdoc.render.html5(doc.contents, wiki_writer);

        try wiki_writer.writeAll(
            \\  </article>
            \\</main>
        );

        var source = std.Io.Reader.fixed(wiki_page.written());

        try render_page(writer, &source, .{
            .title = doc.title,
            .nesting = 1 + doc.nesting,
        });
    }

    fn render_toc(config: Config, writer: *std.Io.Writer, folder: Folder) !void {
        for (folder.files) |entry| {
            switch (entry.content) {
                .folder => |subfolder| {
                    try writer.print("    <li class=\"folder\" data-indent=\"{}\">{f}</li>\n", .{
                        subfolder.nesting,
                        fmt_html(std.fs.path.basename(entry.path)),
                    });
                    try render_toc(config, writer, subfolder);
                },

                .copy => {},

                .document => |document| {
                    try writer.print("    <li class=\"file\" data-indent=\"{}\"><a href=\"{f}\">{f}</a></li>\n", .{
                        document.nesting + 1,
                        fmt_url(config, document.output_path),
                        fmt_html(document.title),
                    });
                },
            }
        }
    }

    pub fn scan_folder(allocator: std.mem.Allocator, path: []const u8, dir: std.fs.Dir, nesting: usize) !Folder {
        var iter = dir.iterate();

        var entries: std.ArrayList(Folder.Item) = .empty;
        defer entries.deinit(allocator);

        while (try iter.next()) |entry| {
            const child_path = try std.fs.path.join(allocator, &.{ path, entry.name });

            switch (entry.kind) {
                .file => {
                    const ext = std.fs.path.extension(entry.name);
                    if (std.mem.eql(u8, ext, ".hdoc")) {

                        // convert hyperdoc
                        std.log.err("conv {s}", .{child_path});

                        const hdoc_text = try dir.readFileAlloc(allocator, entry.name, 1 << 24);
                        defer allocator.free(hdoc_text);

                        var diags: hdoc.Diagnostics = .init(allocator);
                        defer diags.deinit();

                        const doc = hdoc.parse(allocator, hdoc_text, &diags) catch |err| switch (err) {
                            error.OutOfMemory => |e| return e,

                            error.SyntaxError, error.MalformedDocument, error.UnsupportedVersion, error.InvalidUtf8 => {
                                std.log.err("failed to parse {s}: {t}", .{ child_path, err });
                                for (diags.items.items) |diag| {
                                    std.log.err("failed to parse {s}:{}:{}: {f}", .{
                                        child_path,
                                        diag.location.line,
                                        diag.location.column,
                                        diag.code,
                                    });
                                }
                                return error.BadFile;
                            },
                        };

                        const output_path = try std.fmt.allocPrint(allocator, "{s}.html", .{
                            child_path[0 .. child_path.len - ext.len],
                        });

                        try entries.append(allocator, .{
                            .path = child_path,
                            .content = .{
                                .document = .{
                                    .nesting = nesting,
                                    .output_path = output_path,
                                    .title = if (doc.title) |title|
                                        title.simple
                                    else
                                        try allocator.dupe(u8, entry.name[0 .. entry.name.len - ext.len]),
                                    .contents = doc,
                                },
                            },
                        });
                    } else {
                        // copy file
                        std.log.err("copy {s}", .{child_path});

                        try entries.append(allocator, .{
                            .path = child_path,
                            .content = .copy,
                        });
                    }
                },
                .directory => {
                    std.log.err("dir {s}", .{child_path});

                    var sub_dir = try dir.openDir(entry.name, .{ .iterate = true });
                    defer sub_dir.close();

                    try entries.append(allocator, .{
                        .path = child_path,
                        .content = .{
                            .folder = try scan_folder(allocator, child_path, sub_dir, nesting + 1),
                        },
                    });
                },

                else => @panic("unsupported entry type"),
            }
        }

        return .{
            .nesting = nesting,
            .files = try entries.toOwnedSlice(allocator),
        };
    }

    fn fmt_url(config: Config, url: []const u8) std.fmt.Formatter(struct { Config, []const u8 }, format_url) {
        return .{ .data = .{ config, url } };
    }

    fn format_url(options: struct { Config, []const u8 }, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const config, const url = options;

        // TODO: Implement proper URL parsing and escaping

        const wiki_prefix = "wiki:/";
        if (std.mem.startsWith(u8, url, wiki_prefix)) {
            // wiki url
            try writer.splatBytesAll("../", config.base_nesting);

            const ext = std.fs.path.extension(url);

            try writer.writeAll(url[wiki_prefix.len .. url.len - ext.len]);

            try writer.writeAll(".html");
        } else if (std.mem.indexOf(u8, url, "://") != null) {
            // absolute url
            try writer.writeAll(url);
        } else {
            // relative url
            try writer.splatBytesAll("../", config.base_nesting);
            try writer.writeAll(url);
        }
    }
};

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

fn fmt_html(str: []const u8) std.fmt.Formatter([]const u8, format_html_escape) {
    return .{ .data = str };
}

fn fmt_attr(str: []const u8) std.fmt.Formatter([]const u8, format_attr_escape) {
    return .{ .data = str };
}

fn format_html_escape(str: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.writeAll(str); // TODO: Implement proper escaping
}

fn format_attr_escape(str: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.writeAll(str); // TODO: Implement proper escaping
}
