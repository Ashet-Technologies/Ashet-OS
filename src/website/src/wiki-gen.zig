const std = @import("std");
const hdoc = @import("hyperdoc");

const website_gen = @import("website-gen.zig");

const render_page = website_gen.render_page;
const fmt_html = website_gen.fmt_html;
const fmt_url = website_gen.fmt_url;

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

        folder: ?Folder,
        document: ?Document,
        copy: bool,
    };
};

const Document = struct {
    nesting: usize,
    output_path: []const u8,
    title: []const u8,
    contents: hdoc.Document,
};

pub fn render(output_dir: std.fs.Dir, wiki_src_dir: std.fs.Dir, allocator: std.mem.Allocator) !void {
    const root = try scan_folder(allocator, ".", wiki_src_dir, 0);

    try output_dir.deleteTree("wiki");

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
        if (entry.copy) {
            try std.fs.Dir.copyFile(
                input,
                entry.path,
                output,
                entry.path,
                .{},
            );
        }

        if (entry.folder) |subfolder| {
            try output.makeDir(entry.path);
            try render_folder(config, input, output, subfolder);
        }

        if (entry.document) |document| {
            var output_file = try output.createFile(document.output_path, .{ .exclusive = true });
            defer output_file.close();

            var buffer: [8192]u8 = undefined;
            var file_writer = output_file.writer(&buffer);

            try render_html(config, document, &file_writer.interface);

            try file_writer.interface.flush();
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

    try hdoc.render.html5(doc.contents, wiki_writer, .{
        .rewrite_uri_ctx = @constCast(&config),
        .rewrite_uri_fn = rewrite_wiki_url,

        .rewrite_img_ctx = @constCast(&config),
        .rewrite_img_fn = rewrite_img_url,
    });

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

fn rewrite_wiki_url(ctx: ?*anyopaque, url: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    const config: *const Config = @ptrCast(@alignCast(ctx.?));

    // TODO: Implement proper URL parsing and escaping

    const wiki_prefix = "wiki:/";
    if (std.mem.startsWith(u8, url, wiki_prefix)) {
        // wiki url
        try writer.splatBytesAll("../", config.base_nesting - 1);

        const ext = std.fs.path.extension(url);

        try writer.writeAll(url[wiki_prefix.len .. url.len - ext.len]);

        try writer.writeAll(".html");
    } else {
        try writer.print("{f}", .{fmt_url(url, config.base_nesting)});
    }
}

fn rewrite_img_url(ctx: ?*anyopaque, url: []const u8, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    _ = ctx;
    std.log.err("TODO: Implement image rewriting for '{s}'", .{url});
    try writer.writeAll(url);
}

fn render_toc(config: Config, writer: *std.Io.Writer, folder: Folder) !void {
    for (folder.files) |entry| {
        var class_name: []const u8 = "";
        if (entry.document != null)
            class_name = "file";

        if (entry.folder != null)
            class_name = "folder";

        if (entry.document) |document| {
            try writer.print("    <li class=\"{s}\" data-indent=\"{}\"><a href=\"{f}\">{f}</a></li>\n", .{
                class_name,
                document.nesting + 1,
                fmt_url(document.output_path, config.base_nesting),
                fmt_html(document.title),
            });
        }
        if (entry.folder) |subfolder| {
            if (entry.document == null) {
                try writer.print("    <li class=\"{s}\" data-indent=\"{}\">{f}</li>\n", .{
                    class_name,
                    subfolder.nesting,
                    fmt_html(std.fs.path.basename(entry.path)),
                });
            }
            try render_toc(config, writer, subfolder);
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
                    std.log.info("conv {s}", .{child_path});

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
                        .copy = false,
                        .folder = null,
                        .document = .{
                            .nesting = nesting,
                            .output_path = output_path,
                            .title = if (doc.title) |title|
                                title.simple
                            else
                                try allocator.dupe(u8, entry.name[0 .. entry.name.len - ext.len]),
                            .contents = doc,
                        },
                    });
                } else {
                    // copy file
                    std.log.info("copy {s}", .{child_path});

                    try entries.append(allocator, .{
                        .path = child_path,
                        .copy = true,
                        .folder = null,
                        .document = null,
                    });
                }
            },
            .directory => {
                std.log.info("dir {s}", .{child_path});

                var sub_dir = try dir.openDir(entry.name, .{ .iterate = true });
                defer sub_dir.close();

                try entries.append(allocator, .{
                    .path = child_path,
                    .copy = false,
                    .document = null,
                    .folder = try scan_folder(allocator, child_path, sub_dir, nesting + 1),
                });
            },

            else => @panic("unsupported entry type"),
        }
    }

    for (entries.items) |*maybe_folder| {
        if (maybe_folder.folder == null)
            continue;
        std.debug.assert(maybe_folder.document == null);

        const folder_name = std.fs.path.basename(maybe_folder.path);

        for (entries.items) |*maybe_doc| {
            if (maybe_doc.document == null) continue;

            const doc_name = std.fs.path.basename(maybe_doc.path);
            const doc_ext = std.fs.path.extension(doc_name);

            const base_name = doc_name[0 .. doc_name.len - doc_ext.len];

            if (!std.mem.eql(u8, folder_name, base_name))
                continue;

            if (maybe_doc.folder != null) {
                std.debug.panic("mismatch for {s} and {s}", .{ maybe_folder.path, maybe_doc.path });
            }

            maybe_folder.document = maybe_doc.document;
            maybe_doc.document = null;

            std.log.info("fusing folder {s} and document {s}", .{ maybe_folder.path, maybe_doc.path });
            break;
        }
    }

    // Clean all useless items from the list:
    {
        var i: usize = 0;
        while (i < entries.items.len) {
            const entry = &entries.items[i];

            // Keep everything with content:
            if (entry.copy or entry.document != null or entry.folder != null) {
                i += 1;
                continue;
            } else {
                // Drop empty items:
                _ = entries.swapRemove(i);
            }
        }
    }

    std.sort.block(Folder.Item, entries.items, {}, struct {
        fn lt(_: void, lhs: Folder.Item, rhs: Folder.Item) bool {
            return std.ascii.lessThanIgnoreCase(
                name_of(lhs),
                name_of(rhs),
            );
        }

        fn name_of(item: Folder.Item) []const u8 {
            return if (item.document) |doc|
                doc.title
            else
                std.fs.path.basename(item.path);
        }
    }.lt);

    return .{
        .nesting = nesting,
        .files = try entries.toOwnedSlice(allocator),
    };
}
