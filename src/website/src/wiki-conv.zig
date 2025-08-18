const std = @import("std");
const hyperdoc = @import("hyperdoc");

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);

    if (argv.len != 3)
        @panic("wiki-conv <input dir> <output dir>");

    var input_dir = try std.fs.cwd().openDir(argv[1], .{ .iterate = true });
    defer input_dir.close();

    try std.fs.cwd().deleteTree(argv[2]);

    var output_dir = try std.fs.cwd().makeOpenPath(argv[2], .{});
    defer output_dir.close();

    {
        var walker = try input_dir.walk(allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            switch (entry.kind) {
                .file => {
                    const ext = std.fs.path.extension(entry.basename);
                    if (std.mem.eql(u8, ext, ".hdoc")) {

                        // convert hyperdoc
                        std.log.err("conv {s}", .{entry.path});

                        const hdoc_text = try input_dir.readFileAlloc(allocator, entry.path, 1 << 24);
                        defer allocator.free(hdoc_text);

                        var loc: hyperdoc.ErrorLocation = undefined;

                        var doc = hyperdoc.parse(allocator, hdoc_text, &loc) catch |err| {
                            std.log.err("failed to parse {s}:{}:{}: {s}", .{
                                entry.path,
                                loc.line,
                                loc.column,
                                @errorName(err),
                            });
                            return 1;
                        };
                        defer doc.deinit();

                        const fname = try std.fmt.allocPrint(allocator, "{s}.html", .{
                            entry.path[0 .. entry.path.len - ext.len],
                        });
                        defer allocator.free(fname);

                        var output_file = try output_dir.createFile(fname, .{ .exclusive = true });
                        defer output_file.close();

                        var buffered_writer: BufferedWriter = .{ .unbuffered_writer = output_file.writer() };

                        try render_html(doc, buffered_writer.writer());

                        try buffered_writer.flush();
                    } else {
                        // copy file
                        std.log.err("copy {s}", .{entry.path});
                        try std.fs.Dir.copyFile(
                            input_dir,
                            entry.path,
                            output_dir,
                            entry.path,
                            .{},
                        );
                    }
                },

                .directory => {
                    std.log.err("dir {s}", .{entry.path});
                    try output_dir.makeDir(entry.path);
                },

                else => @panic("unsupported file type!"),
            }
        }
    }

    return 0;
}

const BufferedWriter = std.io.BufferedWriter(8192, std.fs.File.Writer);

fn render_html(doc: hyperdoc.Document, writer: BufferedWriter.Writer) !void {
    try writer.writeAll(
        \\<!doctype html>
        \\<html lang="en">
        \\  <head>
        \\    <meta charset="UTF-8">
        \\  </head>
        \\  <body>
        \\
    );

    for (doc.contents) |block| {
        try render_html_block(doc, block, writer);
    }

    try writer.writeAll(
        \\  </body>
        \\</html>
    );
}

fn render_html_block(doc: hyperdoc.Document, block: hyperdoc.Block, writer: BufferedWriter.Writer) !void {
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
                    heading.anchor, // TODO: Add escaping here
                    heading.title, // TODO: Add escaping here
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
                heading.anchor, // TODO: Esacpe
                heading.title,
            });
        },
        .paragraph => |paragraph| {
            try writer.writeAll("  <p>");
            for (paragraph.contents) |span| {
                try render_html_span(doc, span, writer);
            }
            try writer.writeAll("</p>\n");
        },
        .ordered_list => |ordered_list| {
            try writer.writeAll("  <ol>\n");
            for (ordered_list) |item| {
                for (item.contents) |sub_block| {
                    try writer.writeAll("  <li>\n");
                    try render_html_block(doc, sub_block, writer);
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
                    try render_html_block(doc, sub_block, writer);
                    try writer.writeAll("  </li>\n");
                }
            }
            try writer.writeAll("  </ul>\n");
        },
        .quote => |quote| {
            try writer.writeAll("  <blockquote>\n");
            for (quote.contents) |span| {
                try render_html_span(doc, span, writer);
            }
            try writer.writeAll("  </blockquote>\n");
        },
        .preformatted => |preformatted| {
            try writer.writeAll("  <pre><code>");
            for (preformatted.contents) |span| {
                try render_html_span(doc, span, writer);
            }
            try writer.writeAll("</code></pre>\n");
        },
        .image => |image| {
            try writer.print("  <img src=\"{s}\">\n", .{
                image.path, // TODO: Escape
            });
        },
    }
}
fn render_html_span(doc: hyperdoc.Document, span: hyperdoc.Span, writer: BufferedWriter.Writer) !void {
    _ = doc;
    switch (span) {
        .text => |text| {
            try writer.print("{s}", .{text}); // TODO: Escape
        },
        .emphasis => |text| {
            try writer.print("<em>{s}</em>", .{text}); // TODO: Escape
        },
        .monospace => |text| {
            try writer.print("<code>{s}</code>", .{text}); // TODO: Escape
        },
        .link => |link| {
            try writer.print("<a href=\"{s}\">{s}</a>", .{
                link.href, // TODO: Escape
                link.text, // TODO: Escape
            });
        },
    }
}
