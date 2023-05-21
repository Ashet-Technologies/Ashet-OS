const std = @import("std");
const ashet = @import("ashet");
const htext = @import("hypertext");
const hdoc = @import("hyperdoc");
const gui = @import("ashet-gui");

const main_window = @import("ui-layout");

const tree_scrollbar = main_window.tree_scrollbar;
const doc_h_scrollbar = main_window.doc_h_scrollbar;
const doc_v_scrollbar = main_window.doc_v_scrollbar;

pub usingnamespace ashet.core;

const Window = ashet.ui.Window;

var wiki_software: WikiSoftware = undefined;

pub fn main() !void {
    const window = try ashet.ui.createWindow(
        "Hyper Wiki",
        ashet.abi.Size.new(160, 80),
        ashet.abi.Size.max,
        ashet.abi.Size.new(200, 150),
        .{},
    );
    defer ashet.ui.destroyWindow(window);

    for (window.pixels[0 .. window.stride * window.max_size.height]) |*c| {
        c.* = ashet.ui.ColorIndex.get(0xF);
    }

    // Make the window appear and don't block the system
    ashet.process.yield();

    var wiki_root_folder = try ashet.fs.Directory.openDrive(.system, "wiki");
    defer wiki_root_folder.close();

    wiki_software = WikiSoftware{
        .window = window,
        .root_dir = &wiki_root_folder,
        .index = try loadIndex(&wiki_root_folder, ashet.process.allocator()),
    };
    defer wiki_software.index.deinit();

    defer if (wiki_software.document) |*cdoc| {
        cdoc.deinit();
    };

    tree_scrollbar.control.scroll_bar.changedEvent = .{ .id = gui.EventID.from(.treeview_scrolled), .tag = null };

    wiki_software.loadDocumentFromUri("wiki:/welcome.hdoc") catch |err| {
        std.log.err("failed to load document wiki:/welcome.hdoc: {s}", .{@errorName(err)});
    };

    app_loop: while (true) {
        if (wiki_software.relayout_request) {
            wiki_software.doLayout();
        }
        if (wiki_software.repaint_request) {
            wiki_software.paintApp();
        }

        const event = ashet.ui.getEvent(window);
        switch (event) {
            .mouse => |data| {
                if (main_window.interface.sendMouseEvent(data)) |guievt|
                    wiki_software.handleEvent(guievt);
                wiki_software.repaint_request = true;

                if (data.type == .button_press) {
                    var point = Point.new(data.x, data.y);

                    const tree_view_bounds = main_window.tree_view.bounds.shrink(3);
                    const doc_view_bounds = main_window.doc_view.bounds.shrink(3);

                    if (tree_view_bounds.contains(point)) {
                        // sidepanel click
                        if (wiki_software.getClickedLeaf(Point.new(data.x - tree_view_bounds.x, data.y - tree_view_bounds.y))) |leaf| {
                            std.log.info("load document: {s}", .{leaf.file_name});

                            wiki_software.loadDocument(leaf) catch |err| {
                                std.log.err("failed to load document {s}: {s}", .{
                                    leaf.file_name,
                                    @errorName(err),
                                });
                            };
                        }
                    } else if (doc_view_bounds.contains(point)) {
                        // wikitext click

                        if (wiki_software.document) |*current_doc| {
                            const test_point = Point.new(data.x - doc_view_bounds.x, data.y - doc_view_bounds.y);

                            std.log.info("document has {} links:", .{current_doc.links.items.len});
                            const maybe_link = for (current_doc.links.items) |link| {
                                std.log.info("- '{s}', '{s}', {}", .{ link.link.text, link.link.href, link.rect });
                                if (link.rect.contains(test_point))
                                    break link;
                            } else null;

                            if (maybe_link) |slink| {
                                std.log.info("navigate to {s}", .{slink.link.href});
                                wiki_software.loadDocumentFromUri(slink.link.href) catch |err| {
                                    std.log.err("failed to load document {s}: {s}", .{
                                        slink.link.href,
                                        @errorName(err),
                                    });
                                };
                            }
                        }
                    }
                }
            },
            .keyboard => |data| {
                if (main_window.interface.sendKeyboardEvent(data)) |guievt|
                    wiki_software.handleEvent(guievt);
                wiki_software.repaint_request = true;
            },
            .window_close => break :app_loop,
            .window_minimize => {},
            .window_restore => {},
            .window_moving => {},
            .window_moved => {},
            .window_resizing => wiki_software.relayout_request = true,
            .window_resized => wiki_software.relayout_request = true,
        }
    }
}

fn newRect(x: i15, y: i15, w: u16, h: u16) ashet.abi.Rectangle {
    return ashet.abi.Rectangle{
        .x = x,
        .y = y,
        .width = w,
        .height = h,
    };
}

const WikiSoftware = struct {
    repaint_request: bool = true,
    relayout_request: bool = true,

    root_dir: *ashet.fs.Directory,
    window: *const Window,
    index: Index,
    document: ?Document = null,

    fn doLayout(wiki: *WikiSoftware) void {
        main_window.layout(wiki.window);

        {
            var treeview_height: i16 = 1;
            _ = getClickedLeafInner(
                &wiki.index.root,
                Point.new(-1000, -1000),
                1,
                &treeview_height,
            );

            tree_scrollbar.control.scroll_bar.setRange(@intCast(u15, @intCast(u16, treeview_height) -| (main_window.tree_view.bounds.height -| 6)));
        }

        if (wiki.document) |doc| {
            _ = doc;

            const bounds = main_window.doc_view.bounds.shrink(3);
            const doc_size = bounds.size(); //  htext.measureDocument(bounds, doc.hyperdoc, theme.wiki);

            doc_h_scrollbar.control.scroll_bar.setRange(@intCast(u15, @intCast(u16, doc_size.width) -| bounds.width));
            doc_v_scrollbar.control.scroll_bar.setRange(@intCast(u15, @intCast(u16, doc_size.height) -| bounds.height));

            doc_v_scrollbar.control.scroll_bar.setRange(500);
        } else {
            doc_h_scrollbar.control.scroll_bar.setRange(0);
            doc_v_scrollbar.control.scroll_bar.setRange(0);
        }

        wiki.repaint_request = true;
        wiki.relayout_request = false;
    }

    fn paintApp(wiki: *WikiSoftware) void {
        var fb = gui.Framebuffer.forWindow(wiki.window);

        main_window.interface.paint(fb);

        {
            var offset_y: i16 = 1 - @as(i16, tree_scrollbar.control.scroll_bar.level);
            renderSidePanel(
                fb.view(main_window.tree_view.bounds.shrink(3)),
                &wiki.index.root,
                if (wiki.document) |page| page.leaf else null,
                1,
                &offset_y,
            );
        }

        if (wiki.document) |*page| {
            var doc_fb = fb.view(main_window.doc_view.bounds.shrink(3));

            page.links.shrinkRetainingCapacity(0);

            htext.renderDocument(
                doc_fb,
                page.hyperdoc,
                theme.wiki,
                Point.new(0, -@as(i16, doc_v_scrollbar.control.scroll_bar.level)),
                page,
                linkCallback,
            );
        }

        ashet.ui.invalidate(wiki.window, .{
            .x = 0,
            .y = 0,
            .width = fb.width,
            .height = fb.height,
        });
        wiki.repaint_request = false;
    }

    pub fn loadDocumentFromUri(wiki: *WikiSoftware, url_string: []const u8) !void {
        var doc = try fetchDocumentFromUri(wiki.root_dir, &wiki.index, url_string);
        errdefer doc.deinit();

        wiki.setDocument(doc);
    }

    pub fn loadDocument(wiki: *WikiSoftware, leaf: *const Index.Leaf) !void {
        var doc = try fetchDocument(wiki.root_dir, leaf);
        errdefer doc.deinit();

        wiki.setDocument(doc);
    }

    pub fn setDocument(wiki: *WikiSoftware, doc: ?Document) void {
        if (wiki.document) |*old| {
            old.deinit();
        }
        wiki.document = doc;
    }

    fn fetchDocumentFromUri(dir: *ashet.fs.Directory, index: *const Index, url_string: []const u8) !Document {
        const uri = try std.Uri.parse(url_string);

        var arena = std.heap.ArenaAllocator.init(ashet.process.allocator());
        defer arena.deinit();

        const path = try std.Uri.unescapeString(arena.allocator(), uri.path);

        if (std.mem.eql(u8, uri.scheme, "wiki")) {
            if (uri.host != null)
                return error.InvalidUri;

            if (!std.mem.startsWith(u8, path, "/"))
                return error.InvalidUri;

            // uri requires absolute path, but internally we use relative path, so
            // remove leading '/':
            if (index.files.get(path[1..])) |leaf| {
                return try fetchDocument(dir, leaf);
            } else {
                return error.FileNotFound;
            }
        } else if (std.mem.eql(u8, uri.scheme, "file")) {
            //
            @panic("file scheme is not supported yet!");
        } else {
            return error.UnsupportedScheme;
        }
    }

    fn fetchDocument(dir: *ashet.fs.Directory, leaf: *const Index.Leaf) !Document {
        var list = std.ArrayList(u8).init(ashet.process.allocator());
        defer list.deinit();

        var file = try dir.openFile(leaf.file_name, .read_only, .open_existing);
        defer file.close();

        const stat = try file.stat();

        try list.resize(std.math.cast(usize, stat.size) orelse return error.OutOfMemory);

        const len = try file.read(0, list.items);

        std.debug.assert(len == list.items.len);

        var doc = try hdoc.parse(ashet.process.allocator(), list.items, null);
        errdefer doc.deinit();

        return Document{
            .hyperdoc = doc,
            .leaf = leaf,
            .links = std.ArrayList(Document.ScreenLink).init(ashet.process.allocator()),
        };
    }

    fn handleEvent(wiki: *WikiSoftware, evt: gui.Event) void {
        if (evt.id == gui.EventID.from(.treeview_scrolled)) {
            wiki.relayout_request = true;
        } else {
            std.log.info("unhandled event: {}", .{evt});
        }
    }

    fn getClickedLeaf(wiki: *WikiSoftware, testpoint: Point) ?*const Index.Leaf {
        var offset_y: i16 = @as(i16, 1) -| tree_scrollbar.control.scroll_bar.level;
        return getClickedLeafInner(
            &wiki.index.root,
            testpoint,
            1,
            &offset_y,
        );
    }

    fn getClickedLeafInner(list: *const Index.List, testpoint: Point, x: i16, y: *i16) ?*const Index.Leaf {
        for (list.nodes) |*node| {
            switch (node.content) {
                .list => |*sublist| {
                    y.* += 8;
                    if (getClickedLeafInner(sublist, testpoint, x, y)) |leaf|
                        return leaf;
                },
                .leaf => |*leaf| {
                    const rect = Rectangle{ .x = 0, .y = y.*, .width = 10000, .height = 8 };
                    if (rect.contains(testpoint))
                        return leaf;
                    y.* += 8;
                },
            }
        }
        return null;
    }
};

const Point = ashet.ui.Point;
const Size = ashet.ui.Size;
const Rectangle = ashet.ui.Rectangle;
const ColorIndex = ashet.ui.ColorIndex;

const theme = struct {
    const sidepanel_sel = ColorIndex.get(0x12); // gold
    const sidepanel_document_unsel = ColorIndex.get(0x0); // white
    const sidepanel_document_sel = ColorIndex.get(0x0); // black
    const sidepanel_folder = ColorIndex.get(0x9); // bright gray

    const wiki = htext.Theme{
        .text = .{ .color = ColorIndex.get(0x00) }, // black
        .monospace = .{ .color = ColorIndex.get(0x0D) }, // pink
        .emphasis = .{ .color = ColorIndex.get(0x03) }, // dark red
        .link = .{ .color = ColorIndex.get(0x02) }, // blue

        .h1 = .{ .color = ColorIndex.get(0x03) }, // dark red
        .h2 = .{ .color = ColorIndex.get(0x00) }, // black
        .h3 = .{ .color = ColorIndex.get(0x11) }, // dim gray

        .quote_mark_color = ColorIndex.get(0x05), // dark green

        .padding = 4,

        .line_spacing = 2,
        .block_spacing = 6,
    };
};

fn renderSidePanel(fb: gui.Framebuffer, list: *const Index.List, leaf: ?*const Index.Leaf, x: i16, y: *i16) void {
    for (list.nodes) |*node| {
        if (node.content == .leaf and leaf == &node.content.leaf) {
            fb.fillRectangle(
                .{ .x = 0, .y = y.*, .width = fb.width, .height = 8 },
                theme.sidepanel_sel,
            );
        }
        fb.drawString(
            x,
            y.*,
            node.title,
            if (node.content == .leaf)
                if (leaf == &node.content.leaf)
                    theme.sidepanel_document_sel
                else
                    theme.sidepanel_document_unsel
            else
                theme.sidepanel_folder,
            null,
        );
        y.* += 8;
        if (y.* >= fb.height)
            break;
        if (node.content == .list) {
            renderSidePanel(fb, &node.content.list, leaf, x + 6, y);
        }
    }
}

fn linkCallback(page: *Document, rect: ashet.abi.Rectangle, link: hdoc.Link) void {
    page.links.append(.{
        .link = link,
        .rect = rect,
    }) catch std.log.err("failed to append url {s}: out of memory.", .{link.href});
}

const Document = struct {
    hyperdoc: hdoc.Document,
    leaf: *const Index.Leaf,
    links: std.ArrayList(ScreenLink),

    pub fn deinit(doc: *Document) void {
        doc.hyperdoc.deinit();
        doc.* = undefined;
    }
    const ScreenLink = struct {
        link: hdoc.Link,
        rect: Rectangle,
    };
};

const LeafMap = std.StringHashMap(*const Index.Leaf);

const Index = struct {
    arena: std.heap.ArenaAllocator,
    root: List,
    files: LeafMap,

    pub fn deinit(index: *Index) void {
        index.arena.deinit();
        index.* = undefined;
    }

    pub const Node = struct {
        title: []const u8,
        content: union(enum) {
            leaf: Leaf,
            list: List,
        },
    };

    pub const Leaf = struct {
        file_name: []const u8,
    };

    pub const List = struct {
        nodes: []const Node,
    };
};

fn loadIndex(root: *ashet.fs.Directory, allocator: std.mem.Allocator) !Index {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var path_buffer = std.ArrayList(u8).init(arena.allocator());
    defer path_buffer.deinit();

    var root_node = try loadIndexFolder(root, arena.allocator(), &path_buffer);

    var map = LeafMap.init(arena.allocator());
    errdefer map.deinit();

    try populateLeafMap(&map, root_node.nodes);

    return Index{
        .arena = arena,
        .root = root_node,
        .files = map,
    };
}

fn populateLeafMap(leaf_map: *LeafMap, nodes: []const Index.Node) !void {
    for (nodes) |*node| {
        switch (node.content) {
            .list => |*list| {
                try populateLeafMap(leaf_map, list.nodes);
            },
            .leaf => |*leaf| {
                try leaf_map.putNoClobber(leaf.file_name, leaf);
            },
        }
    }
}

fn loadIndexFolder(dir: *ashet.fs.Directory, arena: std.mem.Allocator, path_buffer: *std.ArrayList(u8)) !Index.List {
    const reset_size = path_buffer.items.len;
    defer path_buffer.shrinkRetainingCapacity(reset_size);

    var list = std.ArrayList(Index.Node).init(arena);
    defer list.deinit();

    try dir.reset();
    while (try dir.next()) |entry| {
        const name = entry.getName();

        if (entry.attributes.directory) {
            const node = try list.addOne();
            errdefer _ = list.pop();

            node.* = Index.Node{
                .title = try arena.dupe(u8, name),
                .content = .{
                    .list = undefined,
                },
            };
            errdefer arena.free(node.title);

            var subdir = try dir.openDir(name);
            defer subdir.close();

            defer path_buffer.shrinkRetainingCapacity(reset_size);
            if (reset_size > 0) {
                try path_buffer.append('/');
            }
            try path_buffer.appendSlice(name);

            node.content.list = try loadIndexFolder(&subdir, arena, path_buffer);
        } else if (std.mem.endsWith(u8, name, ".hdoc")) {
            const node = try list.addOne();
            errdefer _ = list.pop();

            node.* = Index.Node{
                .title = undefined,
                .content = .{
                    .leaf = .{
                        .file_name = undefined,
                    },
                },
            };

            defer path_buffer.shrinkRetainingCapacity(reset_size);
            if (reset_size > 0) {
                try path_buffer.append('/');
            }
            try path_buffer.appendSlice(name);

            node.content.leaf.file_name = try arena.dupe(u8, path_buffer.items);
            errdefer arena.free(node.content.leaf.file_name);

            node.title = std.fs.path.basename(node.content.leaf.file_name);
            node.title = node.title[0 .. node.title.len - 5];
        }
    }

    std.sort.sort(
        Index.Node,
        list.items,
        {},
        compareIndexNode,
    );

    return Index.List{
        .nodes = try list.toOwnedSlice(),
    };
}

fn compareIndexNode(ctx: void, lhs: Index.Node, rhs: Index.Node) bool {
    _ = ctx;

    const lhs_folder = (lhs.content == .list);
    const rhs_folder = (rhs.content == .list);

    if (lhs_folder != rhs_folder) {
        if (lhs_folder)
            return true;
    }

    return std.ascii.lessThanIgnoreCase(lhs.title, rhs.title);
}
