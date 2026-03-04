const std = @import("std");
const hdoc = @import("hyperdoc");
const abi_parser = @import("abi-mapper");

const website_gen = @import("website-gen.zig");

const model = abi_parser.model;

const render_page_file = website_gen.render_page_file;
const fmt_html = website_gen.fmt_html;
const fmt_url = website_gen.fmt_url;
const fmt_attr = website_gen.fmt_attr;

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

pub fn render(output_dir: std.fs.Dir, schema: abi_parser.model.Document, allocator: std.mem.Allocator) !void {
    try output_dir.deleteTree("syscalls");

    var syscalls_dst_dir = try output_dir.makeOpenPath("syscalls", .{});
    defer syscalls_dst_dir.close();

    var tree: TreeRenderer = .{
        .allocator = allocator,
        .schema = &schema,
        .stack = .empty,
    };
    defer tree.stack.deinit(allocator);

    try tree.render_declaration(syscalls_dst_dir, "ashet", 0, .{
        .docs = .empty, // TODO: can we add top-level namespace docs?!
        .children = schema.root,
        .full_qualified_name = &.{},
        .data = .namespace,
    });
}

const TreeRenderer = struct {
    stack: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    schema: *const model.Document,

    pub fn render_declaration(html: *TreeRenderer, output_dir: std.fs.Dir, scope_name: []const u8, nesting: usize, decl: model.Declaration) !void {
        try html.stack.append(html.allocator, scope_name);
        defer std.debug.assert(std.mem.eql(u8, html.stack.pop().?, scope_name));

        for (decl.children) |child| {
            const child_name = child.full_qualified_name[child.full_qualified_name.len - 1];

            var child_dir = try output_dir.makeOpenPath(child_name, .{});
            defer child_dir.close();

            try html.render_declaration(child_dir, child_name, nesting + 1, child);
        }

        var index_writer: std.Io.Writer.Allocating = .init(html.allocator);
        defer index_writer.deinit();
        {
            const writer = &index_writer.writer;

            const page_path = html.stack.items[1..]; // always skip the head of the elements

            try render_page_header(writer, page_path, nesting);

            var renderer: PageRenderer = .{
                .writer = writer,
                .allocator = html.allocator,
                .schema = html.schema,
                .scope_fqn = html.stack.items,
            };

            try renderer.render_declaration(decl);

            try render_page_footer(writer);

            try writer.flush();
        }

        var index_reader: std.Io.Reader = .fixed(index_writer.written());

        var title_buf: [512]u8 = undefined;
        const title = if (decl.full_qualified_name.len > 0)
            try std.fmt.bufPrint(&title_buf, "ashet.{f}", .{fmt_fqn(decl.full_qualified_name)})
        else
            "ashet";

        try render_page_file(output_dir, "index.html", &index_reader, .{
            .nesting = nesting + 1,
            .title = title,
        });
    }
};

const PageRenderer = struct {
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    schema: *const model.Document,
    scope_fqn: model.FQN,

    pub fn render_declaration(html: *PageRenderer, decl: model.Declaration) !void {
        try html.writer.print(
            \\<h1>{[1]s}: {[0]f}</h1>
            \\
        ,
            .{
                fmt_fqn(html.scope_fqn),
                @tagName(decl.data),
            },
        );

        if (!decl.docs.is_empty()) {
            try html.writer.writeAll("<section>\n");
            try html.writer.print("<h2>Documentation</h2>\n", .{});
            try html.writer.print("{f}\n", .{html.fmt_docs(decl.docs)});
            try html.writer.writeAll("</section>\n");
        }

        switch (decl.data) {
            .namespace => {},
            .@"struct" => |index| {
                const item = html.schema.structs[@intFromEnum(index)];

                try html.writer.print("<h2>Fields</h2>\n", .{});

                try html.begin_dl();
                for (item.logic_fields) |field| {
                    try html.writer.print("<div id=\"{f}.{s}\">\n", .{
                        fmt_fqn(item.full_qualified_name),
                        field.name,
                    });

                    try html.writer.print("<dt><code>{s}: {f}", .{
                        field.name,
                        html.fmt_type(field.type),
                    });

                    if (field.default) |default| {
                        try html.writer.print(" = {f}", .{html.fmt_value(default)});
                    }

                    try html.writer.writeAll("</code></dt>");

                    if (!field.docs.is_empty()) {
                        try html.writer.print("<dd>{f}</dd>\n", .{html.fmt_docs(field.docs)});
                    }

                    try html.writer.writeAll("</div>\n");
                }
                try html.end_dl();
            },
            .@"union" => |index| {
                const item = html.schema.unions[@intFromEnum(index)];

                try html.writer.print("<h2>Alternatives</h2>\n", .{});

                try html.begin_dl();
                for (item.logic_fields) |field| {
                    try html.dl_item(
                        item.full_qualified_name,
                        field.name,
                        "{s}: {f}",
                        "{f}",
                        .{
                            field.name,
                            html.fmt_type(field.type),
                            html.fmt_docs(field.docs),
                        },
                    );
                }
                try html.end_dl();
            },
            .@"enum" => |index| {
                const enumeration = html.schema.enums[@intFromEnum(index)];

                // TODO: enumeration.backing_type

                try html.writer.print("<h2>Items</h2>\n", .{});

                try html.begin_dl();
                for (enumeration.items) |item| {
                    try html.dl_item(
                        enumeration.full_qualified_name,
                        item.name,
                        "{s} = {}",
                        "{f}",
                        .{
                            item.name,
                            item.value,
                            html.fmt_docs(item.docs),
                        },
                    );
                }

                switch (enumeration.kind) {
                    .open => try html.dl_item(
                        enumeration.full_qualified_name,
                        "...",
                        "...",
                        "<p>This enumeration is non-exhaustive and may assume all values a {s} can represent.</p>",
                        .{@tagName(enumeration.backing_type)},
                    ),
                    .closed => {},
                }

                try html.end_dl();
            },
            .bitstruct => |index| {
                const item = html.schema.bitstructs[@intFromEnum(index)];
                try html.writer.print("<h2>Fields</h2>\n", .{});

                try html.begin_dl();
                for (item.fields) |field| {
                    try html.writer.print("<div id=\"{f}.{s}\">\n", .{
                        fmt_fqn(item.full_qualified_name),
                        field.name orelse "<reserved>",
                    });

                    try html.writer.print("<dt><code>{s}: {f}", .{
                        field.name orelse "<i>reserved</i>",
                        html.fmt_type(field.type),
                    });

                    if (field.default) |default| {
                        try html.writer.print(" = {f}", .{html.fmt_value(default)});
                    }

                    try html.writer.writeAll("</code></dt>");

                    if (!field.docs.is_empty()) {
                        try html.writer.print("<dd>{f}</dd>\n", .{html.fmt_docs(field.docs)});
                    }

                    try html.writer.writeAll("</div>\n");
                }
                try html.end_dl();
            },
            .syscall => |index| {
                const item = html.schema.syscalls[@intFromEnum(index)];

                if (item.logic_inputs.len > 0) {
                    try html.writer.print("<h2>Inputs</h2>\n", .{});

                    try html.begin_dl();
                    for (item.logic_inputs) |param| {
                        // TODO: Handle "param.default"
                        try html.dl_item(
                            item.full_qualified_name,
                            param.name,
                            "{f}: {f}",
                            "{f}",
                            .{
                                std.zig.fmtId(param.name),
                                html.fmt_type(param.type),
                                html.fmt_docs(param.docs),
                            },
                        );
                    }
                    try html.end_dl();
                }

                if (item.logic_outputs.len > 0) {
                    try html.writer.print("<h2>Outputs</h2>\n", .{});

                    try html.begin_dl();
                    for (item.logic_outputs) |param| {
                        // TODO: Handle "param.default"
                        try html.dl_item(
                            item.full_qualified_name,
                            param.name,
                            "{f}: {f}",
                            "{f}",
                            .{
                                std.zig.fmtId(param.name),
                                html.fmt_type(param.type),
                                html.fmt_docs(param.docs),
                            },
                        );
                    }
                    try html.end_dl();
                }

                if (item.errors.len > 0) {
                    try html.writer.print("<h2>Errors</h2>\n", .{});

                    try html.begin_dl();
                    for (item.errors) |err| {
                        try html.dl_item(
                            item.full_qualified_name,
                            err.name,
                            "{f}",
                            "{f}",
                            .{
                                std.zig.fmtId(err.name),
                                html.fmt_docs(err.docs),
                            },
                        );
                    }
                    try html.end_dl();
                }
            },
            .async_call => |index| {
                const item = html.schema.async_calls[@intFromEnum(index)];

                if (item.logic_inputs.len > 0) {
                    try html.writer.print("<h2>Inputs</h2>\n", .{});

                    try html.begin_dl();
                    for (item.logic_inputs) |param| {
                        // TODO: Handle "param.default"
                        try html.dl_item(
                            item.full_qualified_name,
                            param.name,
                            "{f}: {f}",
                            "{f}",
                            .{
                                std.zig.fmtId(param.name),
                                html.fmt_type(param.type),
                                html.fmt_docs(param.docs),
                            },
                        );
                    }
                    try html.end_dl();
                }

                if (item.logic_outputs.len > 0) {
                    try html.writer.print("<h2>Outputs</h2>\n", .{});

                    try html.begin_dl();
                    for (item.logic_outputs) |param| {
                        // TODO: Handle "param.default"
                        try html.dl_item(
                            item.full_qualified_name,
                            param.name,
                            "{f}: {f}",
                            "{f}",
                            .{
                                std.zig.fmtId(param.name),
                                html.fmt_type(param.type),
                                html.fmt_docs(param.docs),
                            },
                        );
                    }
                    try html.end_dl();
                }

                if (item.errors.len > 0) {
                    try html.writer.print("<h2>Errors</h2>\n", .{});

                    try html.begin_dl();
                    for (item.errors) |err| {
                        try html.dl_item(
                            item.full_qualified_name,
                            err.name,
                            "{f}",
                            "{f}",
                            .{
                                std.zig.fmtId(err.name),
                                html.fmt_docs(err.docs),
                            },
                        );
                    }
                    try html.end_dl();
                }
            },
            .resource => |index| {
                const item = html.schema.resources[@intFromEnum(index)];
                _ = item;

                // TODO: Potentially render out the unique id?
                // try html.writer.writeAll("<p>TODO: Implement resource</p>\n");
            },
            .constant => |index| {
                const item = html.schema.constants[@intFromEnum(index)];

                try html.writer.writeAll("<section>\n");

                try html.writer.print("<h2>Definition</h2>\n", .{});

                try html.writer.writeAll("<pre><code>");

                try html.writer.print("<span class=\"tok-kw\">const</span> <span class=\"tok-name\">{f}</span>", .{
                    std.zig.fmtId(item.full_qualified_name[item.full_qualified_name.len - 1]),
                });
                if (item.type) |item_type_id| {
                    try html.writer.print(": <span class=\"tok-type\">{f}</span>", .{
                        html.fmt_type(item_type_id),
                    });
                }
                try html.writer.print(" = {f};", .{
                    html.fmt_value(item.value),
                });

                try html.writer.writeAll("</code></pre>");

                try html.writer.writeAll("</section>\n");
            },
            .typedef => |index| {
                const item = html.schema.types[@intFromEnum(index)].typedef;

                try html.writer.writeAll("<section>\n");

                try html.writer.print("<h2>Definition</h2>\n", .{});

                try html.writer.writeAll("<code>");

                try html.writer.print("<span class=\"tok-kw\">typedef</span> <span class=\"tok-name\">{f}</span>", .{
                    std.zig.fmtId(item.full_qualified_name[item.full_qualified_name.len - 1]),
                });

                try html.writer.print(" = <span class=\"tok-type\">{f}</span>;", .{
                    html.fmt_type(item.alias),
                });

                try html.writer.writeAll("</code>");

                try html.writer.writeAll("</section>\n");
            },
        }

        try html.render_basic_list(decl, "Namespaces", &.{.namespace});
        try html.render_basic_list(decl, "Types", &.{
            .@"struct",
            .@"union",
            .@"enum",
            .bitstruct,
            .resource,
            .typedef,
        });
        try html.render_basic_list(decl, "Constants", &.{.constant});
        try html.render_group(decl, "System Calls", .syscall);
        try html.render_group(decl, "Asynchronous Operations", .async_call);
    }

    fn begin_dl(html: *PageRenderer) !void {
        try html.writer.writeAll("<dl>\n");
    }
    fn end_dl(html: *PageRenderer) !void {
        try html.writer.writeAll("</dl>\n");
    }

    fn dl_item(html: *PageRenderer, fqn: []const []const u8, local_name: ?[]const u8, comptime dt_fmt: []const u8, comptime dd_fmt: []const u8, args: anytype) !void {
        if (local_name) |name| {
            try html.writer.print("<div id=\"{f}.{s}\">", .{ fmt_fqn(fqn), name });
        } else {
            try html.writer.print("<div id=\"{f}\">", .{fmt_fqn(fqn)});
        }

        try html.writer.print(
            "<dt><code>" ++ dt_fmt ++ "</code></dt><dd>" ++ dd_fmt ++ "</dd></div>\n",
            args,
        );
    }

    fn contains_tag(tag: model.Declaration.Kind, tags: []const model.Declaration.Kind) bool {
        for (tags) |t| {
            if (t == tag)
                return true;
        }
        return false;
    }

    pub fn render_basic_list(html: *PageRenderer, decl: model.Declaration, title: []const u8, tags: []const model.Declaration.Kind) !void {
        var count: usize = 0;
        for (decl.children) |child| {
            if (contains_tag(child.data, tags))
                count += 1;
        }

        if (count == 0)
            return;

        try html.writer.writeAll("<section>\n");

        try html.writer.print("            <h2>{s}</h2>\n", .{title});

        try html.writer.writeAll("            <ul class=\"basic-list\">\n");
        for (decl.children) |child| {
            if (!contains_tag(child.data, tags))
                continue;

            try html.writer.print(
                \\                <li><a href="{f}">{s}</a></li>
                \\
            , .{
                html.fmt_page_url(child.full_qualified_name),
                child.full_qualified_name[child.full_qualified_name.len - 1],
            });
        }
        try html.writer.writeAll("            </ul>\n");
        try html.writer.writeAll("</section>\n");
    }

    pub fn render_group(html: *PageRenderer, decl: model.Declaration, title: []const u8, tag: model.Declaration.Kind) !void {
        var count: usize = 0;
        for (decl.children) |child| {
            if (child.data == tag)
                count += 1;
        }

        if (count == 0)
            return;

        try html.writer.writeAll("<section>\n");

        try html.writer.print("            <h2>{s}</h2>\n", .{title});

        try html.writer.writeAll("            <dl>\n");
        for (decl.children) |child| {
            if (child.data != tag)
                continue;

            try html.writer.print("                <div id=\"{f}\">\n", .{fmt_fqn(child.full_qualified_name)});

            try html.writer.print(
                \\                    <dt><code><span class="tok-kw">{s}</span> <a href="{f}"><span class="tok-name">{s}</span></a>(
            , .{
                @tagName(child.data),
                html.fmt_page_url(child.full_qualified_name),
                child.full_qualified_name[child.full_qualified_name.len - 1],
            });

            const maybe_function = switch (child.data) {
                .syscall => |index| html.schema.syscalls[@intFromEnum(index)],
                .async_call => |index| html.schema.async_calls[@intFromEnum(index)],
                else => null,
            };
            if (maybe_function) |function| {
                var has_any = false;

                for (function.logic_inputs) |param| {
                    if (has_any) try html.writer.writeAll(", ");

                    try html.writer.print("<span class=\"tok-kw\">in</span> <span class=\"tok-name\">{s}</span>: {f}", .{
                        param.name,
                        html.fmt_type(param.type),
                    });

                    has_any = true;
                }

                for (function.logic_outputs) |param| {
                    if (has_any) try html.writer.writeAll(", ");

                    try html.writer.print("<span class=\"tok-kw\">out</span> <span class=\"tok-name\">{s}</span>: {f}", .{
                        param.name,
                        html.fmt_type(param.type),
                    });

                    has_any = true;
                }

                try html.writer.writeAll(")");
                if (function.no_return) {
                    try html.writer.writeAll(" <span class=\"tok-kw\">noreturn</span>");
                }
            } else {
                try html.writer.writeAll(")");
            }
            try html.writer.writeAll("</code></dt>");

            if (!child.docs.is_empty()) {
                try html.writer.print(
                    \\                    <dd>{f}</dd>
                    \\
                , .{
                    html.fmt_docs(child.docs),
                });
            }

            try html.writer.writeAll("                </div>\n");
        }
        try html.writer.writeAll("            </dl>\n");
        try html.writer.writeAll("</section>\n");
    }

    fn fmt_type(html: *PageRenderer, type_id: model.TypeIndex) HtmlTypeFmt {
        return .{ .html = html, .type_id = type_id };
    }

    const HtmlTypeFmt = struct {
        html: *PageRenderer,
        type_id: model.TypeIndex,

        pub fn format(self: HtmlTypeFmt, writer: *std.Io.Writer) !void {
            const type_ref = self.html.schema.types[@intFromEnum(self.type_id)];

            switch (type_ref) {
                .well_known => |name| try writer.print("<span class=\"tok-type\">{s}</span>", .{@tagName(name)}),
                .uint => |size| try writer.print("<span class=\"tok-type\">u{}</span>", .{size}),
                .int => |size| try writer.print("<span class=\"tok-type\">i{}</span>", .{size}),

                .@"struct" => |index| try self.html.fmt_known_type(writer, self.html.schema.structs[@intFromEnum(index)]),
                .@"union" => |index| try self.html.fmt_known_type(writer, self.html.schema.unions[@intFromEnum(index)]),
                .@"enum" => |index| try self.html.fmt_known_type(writer, self.html.schema.enums[@intFromEnum(index)]),
                .bitstruct => |index| try self.html.fmt_known_type(writer, self.html.schema.bitstructs[@intFromEnum(index)]),
                .resource => |index| try self.html.fmt_known_type(writer, self.html.schema.resources[@intFromEnum(index)]),
                .typedef => |alias| try self.html.fmt_known_type(writer, alias),

                .optional => |child| try writer.print("?{f}", .{self.html.fmt_type(child)}),
                .array => |array| try writer.print("[{}]{f}", .{ array.size, self.html.fmt_type(array.child) }),

                .alias => |child| try writer.print("{f}", .{self.html.fmt_type(child)}),

                .ptr => |ptr| {
                    try writer.writeAll(switch (ptr.size) {
                        .one => "*",
                        .slice => "[]",
                        .unknown => "[*]",
                    });

                    if (ptr.is_const) {
                        try writer.writeAll("<span class=\"tok-kw\">const</span> ");
                    }

                    if (ptr.alignment) |alignment| {
                        try writer.print("<span class=\"tok-kw\">align</span>({}) ", .{alignment});
                    }

                    try writer.print("{f}", .{self.html.fmt_type(ptr.child)});
                },

                .fnptr => |fnptr| {
                    try writer.writeAll("<span class=\"tok-kw\">fnptr</span> (");

                    for (fnptr.parameters, 0..) |param, index| {
                        if (index > 0)
                            try writer.writeAll(", ");
                        try writer.print("<span class=\"tok-kw\">{f}</span>", .{
                            self.html.fmt_type(param),
                        });
                    }

                    try writer.print(") {f}", .{
                        self.html.fmt_type(fnptr.return_type),
                    });
                },

                .external,
                => try writer.writeAll("&lt;TODO&gt;"),

                .unknown_named_type => @panic("invalid schema!"),
                .unset_magic_type => @panic("invalid schema!"),
            }
        }
    };

    fn fmt_value(html: *PageRenderer, value: model.Value) std.fmt.Formatter(model.Value, format_value) {
        _ = html;
        return .{ .data = value };
    }

    fn fmt_known_type(html: *PageRenderer, writer: *std.Io.Writer, known_type: anytype) !void {
        try writer.print("<a href=\"{f}\"><span class=\"tok-type\">{f}</span></a>", .{
            html.fmt_page_url(known_type.full_qualified_name),
            fmt_fqn(known_type.full_qualified_name),
        });
    }

    fn format_value(value: model.Value, writer: *std.Io.Writer) !void {
        return format_value_inner(value, writer, 1);
    }

    fn format_value_inner(value: model.Value, writer: *std.Io.Writer, nesting: usize) !void {
        const indent = 4;
        switch (value) {
            .null => try writer.writeAll("<span class=\"tok-kw\">null</span>"),
            .bool => |val| try writer.print("{}", .{val}),
            .int => |int| try writer.print("{}", .{int}),
            .string => |text| try writer.print("\"{f}\"", .{std.zig.fmtString(text)}),
            .compound => |compound| {
                try writer.writeAll(".{");
                for (compound.fields.keys(), compound.fields.values()) |key, field| {
                    try writer.writeAll("\n");
                    try writer.splatByteAll(' ', indent * nesting);

                    try writer.print(".<span class=\"tok-name\">{f}</span> = ", .{
                        std.zig.fmtId(key),
                    });

                    try format_value_inner(field, writer, nesting + 1);
                    try writer.writeAll(",");
                }
                try writer.writeAll("\n}");
            },
        }
    }

    fn fmt_page_url(html: *PageRenderer, fqn: model.FQN) std.fmt.Formatter(struct { *PageRenderer, model.FQN }, format_page_url) {
        return .{ .data = .{ html, fqn } };
    }

    fn format_page_url(arguments: struct { *PageRenderer, model.FQN }, writer: *std.Io.Writer) !void {
        const html, const fqn = arguments;

        try writer.splatBytesAll("../", html.scope_fqn.len - 1);

        for (fqn) |part| {
            try writer.print("{s}/", .{part});
        }
        try writer.writeAll("index.html");
    }

    fn fmt_docs(html: *PageRenderer, docs: model.DocComment) DocFmt {
        return .{ .docs = docs, .url_nesting = html.scope_fqn.len - 1, .scope_fqn = html.scope_fqn };
    }
};

fn render_page_header(writer: *std.Io.Writer, namespace_fqn: abi_parser.model.FQN, nesting: usize) !void {
    try writer.writeAll(
        \\<main id="syscalls">
        \\  <nav class="panel breadcrumbs">
        \\    <ul class="breadcrumbs">
    );
    try writer.print(
        \\      <li><a href="{f}">ashet</a></li>
    , .{
        fmt_url("index.html", nesting),
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
            fmt_url(url_writer.buffered(), nesting),
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

fn fmt_fqn(fqn: []const []const u8) std.fmt.Alt([]const []const u8, format_fqn) {
    return .{ .data = fqn };
}

fn format_fqn(fqn: []const []const u8, writer: *std.Io.Writer) !void {
    for (fqn, 0..) |name, i| {
        if (i > 0)
            try writer.writeAll(".");
        try writer.writeAll(name);
    }
}

const DocFmt = struct {
    docs: model.DocComment,
    url_nesting: usize,
    scope_fqn: model.FQN,

    pub fn format(self: DocFmt, writer: *std.Io.Writer) !void {
        if (self.docs.is_empty())
            return;

        for (self.docs.sections) |section| {
            try writer.print("<div class=\"doc-section doc-section-{t}\">\n", .{section.kind});

            for (section.blocks) |block| {
                switch (block) {
                    .paragraph => |p| {
                        try writer.writeAll("<p>\n");
                        try self.format_inlines(p.content, writer);
                        try writer.writeAll("</p>\n");
                    },

                    .ordered_list => |list| {
                        try writer.writeAll("<ol>\n");
                        for (list.items) |item| {
                            try writer.writeAll("<li>\n");
                            try self.format_inlines(item, writer);
                            try writer.writeAll("</li>\n");
                        }
                        try writer.writeAll("</ol>\n");
                    },
                    .unordered_list => |list| {
                        try writer.writeAll("<ul>\n");
                        for (list.items) |item| {
                            try writer.writeAll("<li>\n");
                            try self.format_inlines(item, writer);
                            try writer.writeAll("</li>\n");
                        }
                        try writer.writeAll("</ul>\n");
                    },

                    .code_block => |code| {
                        try writer.writeAll("<pre class=\"codeblock\"");
                        if (code.syntax) |syntax| {
                            try writer.print(" data-syntax=\"{f}\"", .{
                                fmt_attr(syntax),
                            });
                        }
                        try writer.writeAll(">");
                        try writer.print("{f}", .{fmt_attr(code.content)});
                        try writer.writeAll("</pre>\n");
                    },
                }
            }

            try writer.writeAll("</div>\n");
        }
    }

    fn format_inlines(self: DocFmt, inlines: []const model.DocComment.Inline, writer: *std.Io.Writer) !void {
        for (inlines) |span| {
            switch (span) {
                .text => |text| try writer.writeAll(text.value),
                .code => |code| try writer.print("<code>{s}</code>", .{code.value}),
                .emphasis => |emphasis| {
                    try writer.writeAll("<em>");
                    try self.format_inlines(emphasis.content, writer);
                    try writer.writeAll("</em>");
                },
                .ref => |ref| {
                    var url_buffer: [512]u8 = undefined;
                    var url_writer: std.Io.Writer = .fixed(&url_buffer);

                    try url_writer.splatBytesAll("../", self.url_nesting);

                    var pos: usize = 0;
                    while (pos < ref.fqn.len) {
                        const split = std.mem.indexOfScalarPos(u8, ref.fqn, pos, '.') orelse break;
                        try url_writer.print("{s}/", .{ref.fqn[pos..split]});
                        pos = split + 1;
                    }

                    try url_writer.print("index.html#{s}", .{ref.fqn});

                    try writer.print("<a href=\"{f}\">", .{fmt_url(url_writer.buffered(), 0)});
                    try writer.print("<code>{s}</code>", .{self.local_ref_display(ref.fqn)});
                    try writer.writeAll("</a>");
                },
                .link => |link| {
                    try writer.print("<a href=\"{f}\">", .{fmt_attr(link.url)});
                    try self.format_inlines(link.content, writer);
                    try writer.writeAll("</a>");
                },
            }
        }
    }

    /// Returns the locally qualified display name for a ref FQN relative to
    /// this scope. Strips the scope prefix (everything after the root "ashet"
    /// component) when the ref shares it, so refs within the same namespace
    /// are shown without redundant qualification.
    fn local_ref_display(self: DocFmt, ref_fqn: []const u8) []const u8 {
        var pos: usize = 0;
        // scope_fqn[0] is the root "ashet"; refs don't include it, so start at [1]
        for (self.scope_fqn[1..]) |part| {
            if (!std.mem.startsWith(u8, ref_fqn[pos..], part)) break;
            const next = pos + part.len;
            if (next >= ref_fqn.len or ref_fqn[next] != '.') break;
            pos = next + 1;
        }
        return ref_fqn[pos..];
    }
};

