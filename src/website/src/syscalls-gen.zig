const std = @import("std");
const hdoc = @import("hyperdoc");
const abi_parser = @import("abi-mapper");

const website_gen = @import("website-gen.zig");

const render_page_file = website_gen.render_page_file;
const fmt_html = website_gen.fmt_html;
const fmt_url = website_gen.fmt_url;

const Context = struct {
    root_dir: std.fs.Dir,
    abi: abi_parser.model.Document,
    allocator: std.mem.Allocator,
};

const Namespace = struct {
    namespace_dir: std.fs.Dir,
    namespace: []const abi_parser.model.Declaration,
    nesting: usize,

    pub fn close(ns: *Namespace) void {
        ns.namespace_dir.close();
        ns.* = undefined;
    }
};

pub fn render(output_dir: std.fs.Dir, abi: abi_parser.model.Document, allocator: std.mem.Allocator) !void {
    try output_dir.deleteTree("syscalls");

    var syscalls_dst_dir = try output_dir.makeOpenPath("syscalls", .{});
    defer syscalls_dst_dir.close();

    const ctx: Context = .{
        .abi = abi,
        .root_dir = syscalls_dst_dir,
        .allocator = allocator,
    };

    try render_namespace(ctx, syscalls_dst_dir, &.{}, abi.root, 1);
}

fn render_namespace(
    ctx: Context,
    namespace_dir: std.fs.Dir,
    namespace_fqn: abi_parser.model.FQN,
    namespace: []const abi_parser.model.Declaration,
    nesting: usize,
) !void {
    try render_namespace_index(ctx, namespace_dir, namespace_fqn, namespace, nesting);

    // TODO: Render all declaration pages as well
}

fn render_namespace_index(
    ctx: Context,
    namespace_dir: std.fs.Dir,
    namespace_fqn: abi_parser.model.FQN,
    namespace: []const abi_parser.model.Declaration,
    nesting: usize,
) !void {
    var index_writer: std.Io.Writer.Allocating = .init(ctx.allocator);
    defer index_writer.deinit();

    const writer = &index_writer.writer;

    try render_page_header(writer, namespace_fqn, nesting);

    try render_page_footer(writer);

    _ = namespace;

    try writer.flush();

    var index_reader: std.Io.Reader = .fixed(index_writer.written());

    try render_page_file(namespace_dir, "index.html", &index_reader, .{
        .nesting = nesting,
        .title = "namespace?",
    });
}

fn render_page_header(writer: *std.Io.Writer, namespace_fqn: abi_parser.model.FQN, nesting: usize) !void {
    try writer.writeAll(
        \\<main id="syscalls">
        \\  <nav class="panel breadcrumbs">
        \\    <ul class="breadcrumbs">
    );
    try writer.print(
        \\      <li><a href="{f}">ashet</a></li>
    , .{
        fmt_url("index.html", nesting - 1),
    });
    for (namespace_fqn, 0..) |node, depth| {
        var url_buf: [256]u8 = undefined;

        var url_writer: std.Io.Writer = .fixed(&url_buf);
        for (namespace_fqn[0 .. depth + 1]) |part| {
            try url_writer.print("{s}/", .{part});
        }
        try url_writer.writeAll("index.html");

        try writer.print(
            \\      <li><a href="{f}">{f}</a></li>
        , .{
            fmt_url("???", nesting),
            fmt_html(node),
        });
    }
    try writer.writeAll(
        \\    </ul>
        \\  </nav>
        \\<article class="panel docs-container ">
    );
}
fn render_page_footer(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\</article>
    );
}
