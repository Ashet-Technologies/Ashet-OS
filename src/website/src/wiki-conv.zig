const std = @import("std");
const hyperdoc = @import("hyperdoc");

const Config = struct {
    root_path: []const u8,
};

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);

    if (argv.len != 3)
        @panic("wiki-conv <input dir> <output dir>");

    var input_dir = try std.fs.cwd().openDir(argv[1], .{ .iterate = true });
    defer input_dir.close();

    const config: Config = .{
        .root_path = "/Ashet-OS/wiki/",
    };

    const root = try scan_folder(allocator, ".", input_dir);

    var toc: std.ArrayList(u8) = .init(allocator);
    try render_toc(config, toc.writer(), root, 0);

    try std.fs.cwd().deleteTree(argv[2]);

    var output_dir = try std.fs.cwd().makeOpenPath(argv[2], .{});
    defer output_dir.close();

    try render_folder(config, input_dir, output_dir, toc.items, root);

    return 0;
}

const Folder = struct {
    files: []Item,

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
    output_path: []const u8,
    title: []const u8,
    contents: hyperdoc.Document,
};

pub fn scan_folder(allocator: std.mem.Allocator, path: []const u8, dir: std.fs.Dir) !Folder {
    var iter = dir.iterate();

    var entries: std.ArrayList(Folder.Item) = .init(allocator);
    defer entries.deinit();

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

                    var loc: hyperdoc.ErrorLocation = undefined;

                    const doc = hyperdoc.parse(allocator, hdoc_text, &loc) catch |err| {
                        std.log.err("failed to parse {s}:{}:{}: {s}", .{
                            child_path,
                            loc.line,
                            loc.column,
                            @errorName(err),
                        });
                        return error.SyntaxError;
                    };

                    const output_path = try std.fmt.allocPrint(allocator, "{s}.html", .{
                        child_path[0 .. child_path.len - ext.len],
                    });

                    try entries.append(.{
                        .path = child_path,
                        .content = .{
                            .document = .{
                                .output_path = output_path,
                                .title = find_title(doc) orelse try allocator.dupe(u8, entry.name[0 .. entry.name.len - ext.len]),
                                .contents = doc,
                            },
                        },
                    });
                } else {
                    // copy file
                    std.log.err("copy {s}", .{child_path});

                    try entries.append(.{
                        .path = child_path,
                        .content = .copy,
                    });
                }
            },
            .directory => {
                std.log.err("dir {s}", .{child_path});

                var sub_dir = try dir.openDir(entry.name, .{ .iterate = true });
                defer sub_dir.close();

                try entries.append(.{
                    .path = child_path,
                    .content = .{
                        .folder = try scan_folder(allocator, child_path, sub_dir),
                    },
                });
            },

            else => @panic("unsupported entry type"),
        }
    }

    return .{
        .files = try entries.toOwnedSlice(),
    };
}

fn find_title(doc: hyperdoc.Document) ?[]const u8 {
    for (doc.contents) |block| {
        switch (block) {
            .heading => |heading| if (heading.level == .document)
                return heading.title,
            else => {},
        }
    }
    return null;
}

fn render_folder(config: Config, input: std.fs.Dir, output: std.fs.Dir, toc: []const u8, folder: Folder) !void {
    for (folder.files) |entry| {
        switch (entry.content) {
            .folder => |subfolder| {
                try output.makeDir(entry.path);
                try render_folder(config, input, output, toc, subfolder);
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

                var buffered_writer: BufferedWriter = .{ .unbuffered_writer = output_file.writer() };

                try render_html(config, document.contents, toc, buffered_writer.writer());

                try buffered_writer.flush();
            },
        }
    }
}

const BufferedWriter = std.io.BufferedWriter(8192, std.fs.File.Writer);

fn render_html(config: Config, doc: hyperdoc.Document, toc: []const u8, writer: BufferedWriter.Writer) !void {
    try writer.writeAll(
        \\<!doctype html>
        \\<html lang="en">
        \\  <head>
        \\    <meta charset="UTF-8">
        \\
    );

    try writer.print("    <link rel=\"stylesheet\" href=\"{}\">\n", .{
        fmt_url(config, "wiki.css"),
    });

    try writer.writeAll(
        \\    <style>
        \\
    );

    for (0..10) |depth| {
        try writer.print(
            \\      li[data-indent="{[0]}"] {{
            \\          margin-left: {[0]}em;
            \\      }}
            \\
        ,
            .{depth},
        );
    }

    try writer.writeAll(
        \\    </style>
        \\  </head>
        \\  <body>
        \\      <header>
        \\          Ashet Wiki
        \\      </header>
        \\      <nav>
        \\
    );
    try writer.writeAll(toc);
    try writer.writeAll(
        \\      </nav>
        \\      <main>
        \\
    );

    for (doc.contents) |block| {
        try render_html_block(config, doc, block, writer);
    }

    try writer.writeAll(
        \\    </main>
        \\  </body>
        \\</html>
        \\
    );
}

fn render_html_block(config: Config, doc: hyperdoc.Document, block: hyperdoc.Block, writer: BufferedWriter.Writer) !void {
    switch (block) {
        .table_of_contents => {
            try writer.writeAll("  <ol>\n");
            for (doc.contents) |_block| {
                const heading = switch (_block) {
                    .heading => |data| data,
                    else => continue,
                };

                try writer.print(
                    \\    <li><a href="#{s}">{s}</a></li>
                    \\
                , .{
                    fmt_attr(heading.anchor),
                    fmt_html(heading.title),
                });
            }
            try writer.writeAll("  </ol>\n");
        },
        .heading => |heading| {
            const level: u8 = switch (heading.level) {
                .document => 1,
                .chapter => 2,
                .section => 3,
            };
            try writer.print("  <h{} id=\"{s}\">{s}</h{[0]}>\n", .{
                level,
                fmt_attr(heading.anchor),
                fmt_html(heading.title),
            });
        },
        .paragraph => |paragraph| {
            try writer.writeAll("  <p>");
            for (paragraph.contents) |span| {
                try render_html_span(config, doc, span, writer);
            }
            try writer.writeAll("</p>\n");
        },
        .ordered_list => |ordered_list| {
            try writer.writeAll("  <ol>\n");
            for (ordered_list) |item| {
                for (item.contents) |sub_block| {
                    try writer.writeAll("  <li>\n");
                    try render_html_block(config, doc, sub_block, writer);
                    try writer.writeAll("  </li>\n");
                }
            }
            try writer.writeAll("  </ol>\n");
        },
        .unordered_list => |unordered_list| {
            try writer.writeAll("  <ul>\n");
            for (unordered_list) |item| {
                for (item.contents) |sub_block| {
                    try writer.writeAll("  <li>\n");
                    try render_html_block(config, doc, sub_block, writer);
                    try writer.writeAll("  </li>\n");
                }
            }
            try writer.writeAll("  </ul>\n");
        },
        .quote => |quote| {
            try writer.writeAll("  <blockquote>\n");
            for (quote.contents) |span| {
                try render_html_span(config, doc, span, writer);
            }
            try writer.writeAll("  </blockquote>\n");
        },
        .preformatted => |preformatted| {
            try writer.writeAll("  <pre><code>");
            for (preformatted.contents) |span| {
                try render_html_span(config, doc, span, writer);
            }
            try writer.writeAll("</code></pre>\n");
        },
        .image => |image| {
            try writer.print("  <img src=\"{s}\">\n", .{
                fmt_attr(image.path),
            });
        },
    }
}

fn render_html_span(config: Config, doc: hyperdoc.Document, span: hyperdoc.Span, writer: BufferedWriter.Writer) !void {
    _ = doc;
    switch (span) {
        .text => |text| try writer.print("{s}", .{fmt_html(text)}),
        .emphasis => |text| try writer.print("<em>{s}</em>", .{fmt_html(text)}),
        .monospace => |text| try writer.print("<code>{s}</code>", .{fmt_html(text)}),
        .link => |link| try writer.print("<a href=\"{s}\">{s}</a>", .{
            fmt_url(config, link.href),
            fmt_html(link.text),
        }),
    }
}

fn render_toc(config: Config, writer: std.ArrayList(u8).Writer, folder: Folder, level: usize) !void {
    for (folder.files) |entry| {
        switch (entry.content) {
            .folder => |subfolder| {
                try writer.print("    <li data-indent=\"{}\">{s}</li>\n", .{
                    level,
                    fmt_html(std.fs.path.basename(entry.path)),
                });
                try render_toc(config, writer, subfolder, level + 1);
            },

            .copy => {},

            .document => |document| {
                try writer.print("    <li data-indent=\"{}\"><a href=\"{s}\">{s}</a></li>\n", .{
                    level,
                    fmt_url(config, document.output_path),
                    fmt_html(document.title),
                });
            },
        }
    }
}

fn fmt_html(str: []const u8) std.fmt.Formatter(format_html_escape) {
    return .{ .data = str };
}

fn fmt_attr(str: []const u8) std.fmt.Formatter(format_attr_escape) {
    return .{ .data = str };
}

fn fmt_url(config: Config, url: []const u8) std.fmt.Formatter(format_url) {
    return .{ .data = .{ config, url } };
}

fn format_html_escape(str: []const u8, fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = opt;

    try writer.writeAll(str); // TODO: Implement proper escaping
}

fn format_attr_escape(str: []const u8, fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = opt;

    try writer.writeAll(str); // TODO: Implement proper escaping
}

fn format_url(options: struct { Config, []const u8 }, fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = opt;

    const config, const url = options;

    // TODO: Implement proper URL parsing and escaping

    const wiki_prefix = "wiki:/";
    if (std.mem.startsWith(u8, url, wiki_prefix)) {
        // wiki url
        try writer.writeAll(config.root_path);

        const ext = std.fs.path.extension(url);

        try writer.writeAll(url[wiki_prefix.len .. url.len - ext.len]);

        try writer.writeAll(".html");
    } else if (std.mem.indexOf(u8, url, "://") != null) {
        // absolute url
        try writer.writeAll(url);
    } else {
        // relative url
        try writer.writeAll(config.root_path);
        try writer.writeAll(url);
    }
}
