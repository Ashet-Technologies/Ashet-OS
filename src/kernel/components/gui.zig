const std = @import("std");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.gui);

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
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);

    system_resource: ashet.resources.SystemResource = .{ .type = .desktop },

    associated_memory: std.heap.ArenaAllocator,

    global_link_node: DesktopList.Node = .{ .data = {} },

    windows: WindowDesktopLinkList = .{},

    server_process: *ashet.multi_tasking.Process,

    name: [:0]const u8,

    window_data_size: usize,
    handle_event: *const fn (ashet.abi.Desktop, *const ashet.abi.DesktopEvent) callconv(.C) void,

    pub fn create(
        server_process: *ashet.multi_tasking.Process,
        name: []const u8,
        descriptor: ashet.abi.DesktopDescriptor,
    ) error{SystemResources}!*Desktop {
        const desktop = ashet.memory.type_pool(Desktop).alloc() catch return error.SystemResources;
        errdefer ashet.memory.type_pool(Desktop).free(desktop);

        desktop.* = .{
            .associated_memory = std.heap.ArenaAllocator.init(ashet.memory.allocator),
            .server_process = server_process,

            .name = "<unset>",

            .window_data_size = descriptor.window_data_size,
            .handle_event = descriptor.handle_event,
        };
        errdefer desktop.associated_memory.deinit();

        desktop.name = desktop.associated_memory.allocator().dupeZ(u8, name) catch return error.SystemResources;

        all_desktops.append(&desktop.global_link_node);

        return desktop;
    }

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(desktop: *Desktop) void {
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
                window.destroy();
            }
        }

        desktop.associated_memory.deinit();
        ashet.memory.type_pool(Desktop).free(desktop);
    }

    fn process_event(desktop: *Desktop, event: ashet.abi.DesktopEvent) void {
        const desktop_handle = ashet.resources.get_handle(desktop.server_process, &desktop.system_resource) orelse @panic("process_event called for a process that does not own the desktop");

        ashet.multi_tasking.call_inside_process(
            desktop.server_process,
            desktop.handle_event,
            .{
                desktop_handle.unsafe_cast(.desktop),
                &event,
            },
        );
    }

    fn notify_create_window(desktop: *Desktop, window: *Window) error{SystemResources}!void {
        const window_handle = try ashet.resources.add_to_process(desktop.server_process, &window.system_resource);

        desktop.process_event(.{
            .create_window = .{
                .event_type = .create_window,
                .window = window_handle.unsafe_cast(.window),
            },
        });
    }

    fn notify_destroy_window(desktop: *Desktop, window: *Window) void {
        const window_handle = ashet.resources.get_handle(desktop.server_process, &window.system_resource) orelse return;
        desktop.process_event(.{
            .create_window = .{
                .event_type = .destroy_window,
                .window = window_handle.unsafe_cast(.window),
            },
        });
    }

    fn notify_show_notification(desktop: *Desktop, message: []const u8, severity: ashet.abi.NotificationSeverity) void {
        _ = desktop;
        _ = message;
        _ = severity;
        @panic("show notification not implemented yet!");
    }

    fn notify_show_message_box(
        desktop: *Desktop,
        message: []const u8,
        caption: []const u8,
        buttons: ashet.abi.MessageBoxButtons,
        icon: ashet.abi.MessageBoxIcon,
    ) void {
        //
        _ = desktop;
        _ = message;
        _ = caption;
        _ = buttons;
        _ = icon;
        @panic("show message box not implemented yet!");
    }
};

pub const Window = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);

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
        errdefer window.associated_memory.deinit();

        window.window_data = window.associated_memory.allocator().alignedAlloc(u8, 16, desktop.window_data_size) catch return error.SystemResources;
        @memset(window.window_data, 0);

        window.title = window.associated_memory.allocator().dupeZ(u8, title) catch return error.SystemResources;

        desktop.windows.append(&window.desktop);
        errdefer desktop.windows.remove(&window.desktop);

        // Invoke the handler process:
        try desktop.notify_create_window(window);

        return window;
    }

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(window: *Window) void {
        const desktop: *Desktop = window.desktop.data.desktop;

        // Invoke the handler process:
        desktop.notify_destroy_window(window);

        desktop.windows.remove(&window.desktop);
        ashet.memory.type_pool(Window).free(window);
    }
};

pub const Widget = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);
    system_resource: ashet.resources.SystemResource = .{ .type = .widget },

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(sock: *Widget) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};

pub const WidgetType = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);
    system_resource: ashet.resources.SystemResource = .{ .type = .widget_type },

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(sock: *WidgetType) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};

pub fn schedule_get_window_event(call: *ashet.overlapped.AsyncCall, inputs: ashet.abi.gui.GetWindowEvent.Inputs) void {
    //
    _ = call;
    _ = inputs;
    logger.warn("TODO: implement schedule_get_window_event", .{});
}
