const std = @import("std");
const ashet = @import("ashet");
const htext = @import("hypertext");
const hdoc = @import("hyperdoc");
const gui = @import("ashet-gui");

const MainWindow = @import("ui.zig");

var main_window: MainWindow = undefined;

pub usingnamespace ashet.core;

const Window = ashet.gui.Window;
const Framebuffer = ashet.graphics.Framebuffer;

var wiki_software: WikiSoftware = undefined;

var title_font: ashet.graphics.Font = undefined;
var sans_font: ashet.graphics.Font = undefined;
var mono_font: ashet.graphics.Font = undefined;

fn load_font(dir: ashet.fs.Directory, path: []const u8) !ashet.graphics.Framebuffer {
    var file = try dir.openFile(path, .read_only, .open_existing);
    defer file.close();

    return try ashet.graphics.load_bitmap_file(file);
}

pub fn main() !void {
    var argv_buffer: [8]ashet.abi.SpawnProcessArg = undefined;
    const argv_len = ashet.userland.process.get_arguments(null, &argv_buffer);
    const argv = argv_buffer[0..argv_len];

    std.debug.assert(argv.len == 2);
    std.debug.assert(argv[0].type == .string);
    std.debug.assert(argv[1].type == .resource);

    const desktop = try argv[1].value.resource.cast(.desktop);

    try gui.init();

    {
        var system_icons = try ashet.fs.Directory.openDrive(.system, "system/icons");
        defer system_icons.close();

        main_window.linkAndInit(.{
            .back = try load_font(system_icons, "back.abm"),
            .forward = try load_font(system_icons, "forward.abm"),
            .home = try load_font(system_icons, "home.abm"),
            .menu = try load_font(system_icons, "menu.abm"),
        });
    }

    title_font = try ashet.graphics.get_system_font("sans");
    sans_font = try ashet.graphics.get_system_font("sans-6");
    mono_font = try ashet.graphics.get_system_font("mono-6");

    // const h1_font = blk: {
    //     var clone = title_font;
    //     clone.vector.size = 8;
    //     clone.vector.bold = true;
    //     break :blk clone;
    // };
    // const h2_font = blk: {
    //     var clone = title_font;
    //     clone.vector.size = 7;
    //     clone.vector.bold = false;
    //     break :blk clone;
    // };
    // const h3_font = blk: {
    //     var clone = title_font;
    //     clone.vector.size = 6;
    //     clone.vector.bold = false;
    //     break :blk clone;
    // };

    const h1_font = title_font;
    const h2_font = title_font;
    const h3_font = title_font;

    theme.wiki.text.font = &sans_font;
    theme.wiki.link.font = &sans_font;
    theme.wiki.emphasis.font = &mono_font;
    theme.wiki.monospace.font = &mono_font;
    theme.wiki.h1.font = &h1_font;
    theme.wiki.h2.font = &h2_font;
    theme.wiki.h3.font = &h3_font;

    const window = try ashet.gui.create_window(
        desktop,
        .{
            .title = "Hyper Wiki",
            .min_size = ashet.abi.Size.new(160, 80),
            .max_size = ashet.abi.Size.max,
            .initial_size = ashet.abi.Size.new(200, 150),
        },
    );
    defer window.destroy_now();

    const framebuffer = try ashet.graphics.create_window_framebuffer(window);
    defer framebuffer.release();

    var command_queue = try ashet.graphics.CommandQueue.init(ashet.process.mem.allocator());
    defer command_queue.deinit();

    try command_queue.clear(ashet.graphics.known_colors.white);
    try command_queue.submit(framebuffer, .{});

    // Make the window appear and don't block the system
    ashet.process.thread.yield();

    var wiki_root_folder = try ashet.fs.Directory.openDrive(.system, "wiki");
    defer wiki_root_folder.close();

    wiki_software = WikiSoftware{
        .window = window,
        .root_dir = &wiki_root_folder,
        .index = try loadIndex(&wiki_root_folder, ashet.process.mem.allocator()),
    };
    defer wiki_software.index.deinit();

    defer if (wiki_software.document) |*cdoc| {
        cdoc.deinit();
    };

    main_window.tree_scrollbar.control.scroll_bar.changedEvent = .{ .id = gui.EventID.from(.treeview_scrolled), .tag = null };
    main_window.doc_h_scrollbar.control.scroll_bar.changedEvent = .{ .id = gui.EventID.from(.document_scrolled), .tag = null };
    main_window.doc_v_scrollbar.control.scroll_bar.changedEvent = .{ .id = gui.EventID.from(.document_scrolled), .tag = null };

    wiki_software.loadDocumentFromUri("wiki:/welcome.hdoc") catch |err| {
        std.log.err("failed to load document wiki:/welcome.hdoc: {s}", .{@errorName(err)});
    };

    var last_size = ashet.graphics.get_framebuffer_size(framebuffer) catch @panic("invalid framebuffer");

    app_loop: while (true) {
        const window_size = ashet.graphics.get_framebuffer_size(framebuffer) catch @panic("invalid framebuffer");
        {
            if (!last_size.eql(window_size)) {
                wiki_software.relayout_request = true;
                last_size = window_size;
            }
        }

        if (wiki_software.relayout_request) {
            wiki_software.doLayout(window_size);
        }
        if (wiki_software.repaint_request) {
            try wiki_software.paintApp(framebuffer, &command_queue);
        }

        const event_out = try ashet.overlapped.performOne(ashet.gui.GetWindowEvent, .{
            .window = window,
        });

        const event = event_out.event;

        switch (event.event_type) {
            .mouse_enter,
            .mouse_leave,
            .mouse_motion,
            .mouse_button_press,
            .mouse_button_release,
            => {
                const data = event.mouse;
                if (main_window.interface.sendMouseEvent(data)) |guievt|
                    wiki_software.handleEvent(guievt);

                if (event.event_type == .mouse_button_press) {
                    const point = Point.new(data.x, data.y);

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

            .key_press, .key_release => {
                const data = event.keyboard;
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

            .widget_notify => {},
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
    window: Window,
    index: Index,
    document: ?Document = null,

    fn doLayout(wiki: *WikiSoftware, size: Size) void {
        main_window.layout(Rectangle.new(Point.zero, size));

        {
            var treeview_height: i16 = 1;
            _ = getClickedLeafInner(
                &wiki.index.root,
                Point.new(-1000, -1000),
                1,
                &treeview_height,
            );

            main_window.tree_scrollbar.control.scroll_bar.setRange(@as(u15, @intCast(@as(u16, @intCast(treeview_height)) -| (main_window.tree_view.bounds.height -| 6))));
        }

        if (wiki.document) |doc| {
            _ = doc;

            const bounds = main_window.doc_view.bounds.shrink(3);
            const doc_size = bounds.size(); //  htext.measureDocument(bounds, doc.hyperdoc, theme.wiki);

            main_window.doc_h_scrollbar.control.scroll_bar.setRange(@as(u15, @intCast(@as(u16, @intCast(doc_size.width)) -| bounds.width)));
            main_window.doc_v_scrollbar.control.scroll_bar.setRange(@as(u15, @intCast(@as(u16, @intCast(doc_size.height)) -| bounds.height)));

            main_window.doc_v_scrollbar.control.scroll_bar.setRange(500);
        } else {
            main_window.doc_h_scrollbar.control.scroll_bar.setRange(0);
            main_window.doc_v_scrollbar.control.scroll_bar.setRange(0);
        }

        wiki.repaint_request = true;
        wiki.relayout_request = false;
    }

    fn paintApp(wiki: *WikiSoftware, fb: ashet.graphics.Framebuffer, q: *ashet.graphics.CommandQueue) !void {
        try q.clear(ashet.graphics.known_colors.white);

        try main_window.interface.paint(q);

        // TODO:
        // {
        //     var offset_y: i16 = 1 - @as(i16, main_window.tree_scrollbar.control.scroll_bar.level);
        //     renderSidePanel(
        //         fb.view(main_window.tree_view.bounds.shrink(3)),
        //         &wiki.index.root,
        //         if (wiki.document) |page| page.leaf else null,
        //         1,
        //         &offset_y,
        //     );
        // }

        // if (wiki.document) |*page| {
        //     const doc_fb = fb.view(main_window.doc_view.bounds.shrink(4));

        //     page.links.shrinkRetainingCapacity(0);

        //     htext.renderDocument(
        //         doc_fb,
        //         page.hyperdoc,
        //         theme.wiki,
        //         Point.new(0, -@as(i16, main_window.doc_v_scrollbar.control.scroll_bar.level)),
        //         page,
        //         linkCallback,
        //     );
        // }

        try q.submit(fb, .{});
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

        main_window.doc_h_scrollbar.control.scroll_bar.level = 0;
        main_window.doc_v_scrollbar.control.scroll_bar.level = 0;
        wiki.document = doc;

        wiki_software.relayout_request = true;
    }

    fn fetchDocumentFromUri(dir: *ashet.fs.Directory, index: *const Index, url_string: []const u8) !Document {
        const uri = try std.Uri.parse(url_string);

        var arena = std.heap.ArenaAllocator.init(ashet.process.mem.allocator());
        defer arena.deinit();

        const path = try uri.path.toRawMaybeAlloc(arena.allocator());

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
        var list = std.ArrayList(u8).init(ashet.process.mem.allocator());
        defer list.deinit();

        var file = try dir.openFile(leaf.file_name, .read_only, .open_existing);
        defer file.close();

        const stat = try file.stat();

        try list.resize(std.math.cast(usize, stat.size) orelse return error.OutOfMemory);

        const len = try file.read(0, list.items);

        std.debug.assert(len == list.items.len);

        var doc = try hdoc.parse(ashet.process.mem.allocator(), list.items, null);
        errdefer doc.deinit();

        return Document{
            .hyperdoc = doc,
            .leaf = leaf,
            .links = std.ArrayList(Document.ScreenLink).init(ashet.process.mem.allocator()),
        };
    }

    fn handleEvent(wiki: *WikiSoftware, evt: gui.Event) void {
        if (evt.id == gui.EventID.from(.treeview_scrolled)) {
            wiki.relayout_request = true;
        } else if (evt.id == gui.EventID.from(.document_scrolled)) {
            wiki_software.repaint_request = true;
        } else {
            std.log.info("unhandled event: {}", .{evt});
        }
    }

    fn getClickedLeaf(wiki: *WikiSoftware, testpoint: Point) ?*const Index.Leaf {
        var offset_y: i16 = @as(i16, 1) -| main_window.tree_scrollbar.control.scroll_bar.level;
        return getClickedLeafInner(
            &wiki.index.root,
            testpoint,
            1,
            &offset_y,
        );
    }

    fn getClickedLeafInner(list: *const Index.List, testpoint: Point, x: i16, y: *i16) ?*const Index.Leaf {
        const font = &sans_font;
        const line_height = font.lineHeight();
        for (list.nodes) |*node| {
            switch (node.content) {
                .list => |*sublist| {
                    y.* += line_height;
                    if (getClickedLeafInner(sublist, testpoint, x, y)) |leaf|
                        return leaf;
                },
                .leaf => |*leaf| {
                    const rect = Rectangle{ .x = 0, .y = y.*, .width = 10000, .height = line_height };
                    if (rect.contains(testpoint))
                        return leaf;
                    y.* += line_height;
                },
            }
        }
        return null;
    }
};

const Point = ashet.graphics.Point;
const Size = ashet.graphics.Size;
const Rectangle = ashet.graphics.Rectangle;
const ColorIndex = ashet.graphics.ColorIndex;

const theme = struct {
    const sidepanel_sel = ColorIndex.get(0x12); // gold
    const sidepanel_document_unsel = ColorIndex.get(0x0); // white
    const sidepanel_document_sel = ColorIndex.get(0x0); // black
    const sidepanel_folder = ColorIndex.get(0x9); // bright gray

    var wiki = htext.Theme{
        .text = .{ .font = undefined, .color = ColorIndex.get(0x00) }, // black
        .monospace = .{ .font = undefined, .color = ColorIndex.get(0x03) }, // dark red
        .emphasis = .{ .font = undefined, .color = ColorIndex.get(0x12) }, // gold
        .link = .{ .font = undefined, .color = ColorIndex.get(0x02) }, // blue

        .h1 = .{ .font = undefined, .color = ColorIndex.get(0x03) }, // dark red
        .h2 = .{ .font = undefined, .color = ColorIndex.get(0x00) }, // black
        .h3 = .{ .font = undefined, .color = ColorIndex.get(0x11) }, // dim gray

        .quote_mark_color = ColorIndex.get(0x05), // dark green

        .padding = 4,

        .line_spacing = 2,
        .block_spacing = 6,
    };
};

fn renderSidePanel(fb: Framebuffer, list: *const Index.List, leaf: ?*const Index.Leaf, x: i16, y: *i16) void {
    const font = &sans_font;

    for (list.nodes) |*node| {
        const line_height = font.lineHeight();

        if (node.content == .leaf and leaf == &node.content.leaf) {
            fb.fillRectangle(
                .{ .x = 0, .y = y.*, .width = fb.width, .height = line_height + 1 },
                theme.sidepanel_sel,
            );
        }

        fb.drawString(
            x,
            y.*,
            node.title,
            font,
            if (node.content == .leaf)
                if (leaf == &node.content.leaf)
                    theme.sidepanel_document_sel
                else
                    theme.sidepanel_document_unsel
            else
                theme.sidepanel_folder,
            null,
        );
        y.* += line_height;
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

    const root_node = try loadIndexFolder(root, arena.allocator(), &path_buffer);

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

    std.sort.block(
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
        return lhs_folder;
    }

    return std.ascii.lessThanIgnoreCase(lhs.title, rhs.title);
}
