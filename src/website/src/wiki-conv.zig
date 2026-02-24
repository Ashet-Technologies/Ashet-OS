const std = @import("std");
const hyperdoc = @import("hyperdoc");

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

fn render_html(config: Config, doc: hyperdoc.Document, toc: []const u8, writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\<!doctype html>
        \\<html lang="en">
        \\  <head>
        \\    <meta charset="UTF-8">
        \\
    );

    try writer.print("    <link rel=\"stylesheet\" href=\"{f}\">\n", .{
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

fn render_html_block(config: Config, doc: hyperdoc.Document, block: hyperdoc.Block, writer: *std.Io.Writer) !void {
    switch (block) {
        .table_of_contents => {
            try writer.writeAll("  <ol>\n");
            for (doc.contents) |_block| {
                const heading = switch (_block) {
                    .heading => |data| data,
                    else => continue,
                };

                try writer.print(
                    \\    <li><a href="#{f}">{f}</a></li>
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
            try writer.print("  <h{} id=\"{f}\">{f}</h{[0]}>\n", .{
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
            try writer.print("  <img src=\"{f}\">\n", .{
                fmt_attr(image.path),
            });
        },
    }
}

fn render_html_span(config: Config, doc: hyperdoc.Document, span: hyperdoc.Span, writer: *std.Io.Writer) !void {
    _ = doc;
    switch (span) {
        .text => |text| try writer.print("{f}", .{fmt_html(text)}),
        .emphasis => |text| try writer.print("<em>{f}</em>", .{fmt_html(text)}),
        .monospace => |text| try writer.print("<code>{f}</code>", .{fmt_html(text)}),
        .link => |link| try writer.print("<a href=\"{f}\">{f}</a>", .{
            fmt_url(config, link.href),
            fmt_html(link.text),
        }),
    }
}
