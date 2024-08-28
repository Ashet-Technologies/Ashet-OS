const std = @import("std");
const ashet = @import("../main.zig");

const Size = ashet.abi.Size;
const CreateWindowFlags = ashet.abi.CreateWindowFlags;

const WindowDesktopLink = struct {
    desktop: *Desktop,
};
const WindowDesktopLinkList = std.DoublyLinkedList(WindowDesktopLink);
const WindowDesktopLinkNode = WindowDesktopLinkList.Node;

const DesktopList = std.DoublyLinkedList(void);

var all_desktops: DesktopList = .{};

pub const DesktopIterator = struct {
    node: ?*DesktopList.Node,

    pub fn next(iter: *DesktopIterator) ?*Desktop {
        const current = iter.node orelse return null;
        iter.node = current.next;

        return @fieldParentPtr("global_link_node", current);
    }
};

/// Returns an interator over all currently active desktops.
pub fn iterate_desktops() DesktopIterator {
    return DesktopIterator{
        .node = all_desktops.first,
    };
}

pub const Desktop = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .desktop },

    associated_memory: std.heap.ArenaAllocator,

    global_link_node: DesktopList.Node = .{ .data = {} },

    windows: WindowDesktopLinkList = .{},

    name: [:0]const u8,
    descriptor: ashet.abi.DesktopDescriptor,

    pub fn create(
        name: []const u8,
        descriptor: ashet.abi.DesktopDescriptor,
    ) error{SystemResources}!*Desktop {
        const desktop = ashet.memory.type_pool(Desktop).alloc() catch return error.SystemResources;
        errdefer ashet.memory.type_pool(Desktop).free(desktop);

        desktop.* = .{
            .associated_memory = std.heap.ArenaAllocator.init(ashet.memory.allocator),
            .name = "<unset>",
            .descriptor = descriptor,
        };
        errdefer desktop.associated_memory.deinit();

        desktop.name = desktop.associated_memory.allocator().dupeZ(u8, name) catch return error.SystemResources;

        all_desktops.append(&desktop.global_link_node);

        return desktop;
    }

    pub fn destroy(desktop: *Desktop) void {
        all_desktops.remove(&desktop.global_link_node);

        // Destroy all associated windows:
        {
            var iter = desktop.windows.first;
            while (iter) |node| {
                // first iterate
                iter = node.next;

                // then destroy, as destroying the window will also kill
                // `node`:
                const window = Window.from_node(node);
                window.system_resource.destroy();
            }
        }

        desktop.associated_memory.deinit();
        ashet.memory.type_pool(Desktop).free(desktop);
    }
};

pub const Window = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .window },

    desktop: WindowDesktopLinkNode,

    associated_memory: std.heap.ArenaAllocator,

    title: [:0]const u8,

    min_size: Size,
    max_size: Size,
    size: Size,

    is_popup: bool,

    window_data: []align(16) u8,

    fn from_node(node: *WindowDesktopLinkNode) *Window {
        return @fieldParentPtr("desktop", node);
    }

    pub fn create(
        desktop: *Desktop,
        title: []const u8,
        min: Size,
        max: Size,
        startup: Size,
        flags: CreateWindowFlags,
    ) error{SystemResources}!*Window {
        const window = ashet.memory.type_pool(Window).alloc() catch return error.SystemResources;
        errdefer ashet.memory.type_pool(Window).free(window);

        window.* = .{
            .associated_memory = std.heap.ArenaAllocator.init(ashet.memory.allocator),
            .min_size = min,
            .max_size = max,
            .size = startup,
            .is_popup = flags.popup,
            .desktop = .{ .data = .{ .desktop = desktop } },
            .title = "<unset>",
            .window_data = undefined,
        };

        window.window_data = window.associated_memory.allocator().alignedAlloc(u8, 16, desktop.descriptor.window_data_size) catch return error.SystemResources;
        window.title = window.associated_memory.allocator().dupeZ(u8, title) catch return error.SystemResources;

        @memset(window.window_data, 0);

        desktop.windows.append(&window.desktop);

        return window;
    }

    pub fn destroy(window: *Window) void {
        const desktop: *Desktop = window.desktop.data.desktop;

        // TODO: Notify desktop of window destruction!

        desktop.windows.remove(&window.desktop);
        ashet.memory.type_pool(Window).free(window);
    }
};

pub const Widget = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .widget },

    pub fn destroy(sock: *Widget) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};

pub const WidgetType = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .widget_type },

    pub fn destroy(sock: *WidgetType) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};
