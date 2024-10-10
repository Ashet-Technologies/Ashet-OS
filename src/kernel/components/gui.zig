const std = @import("std");
const astd = @import("ashet-std");
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

    pub fn process_event(desktop: *Desktop, event: ashet.abi.DesktopEvent) void {
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
        const window_handle = ashet.resources.get_handle(desktop.server_process, &window.system_resource) orelse {
            logger.warn("failed to send destroy_window notification: window does not exist anymore!", .{});
            return;
        };
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
    pub const Destructor = ashet.resources.DestructorWithNotification(@This(), _internal_destroy, _notify_destroy);

    pub const event_queue_len = 16;

    system_resource: ashet.resources.SystemResource = .{ .type = .window },
    associated_memory: std.heap.ArenaAllocator,

    // Desktop data:
    desktop: WindowDesktopLinkNode,
    window_data: []align(16) u8,

    // Metadata:
    title: [:0]const u8,

    min_size: Size,
    max_size: Size,
    size: Size,

    is_popup: bool,

    // Rendering:
    pixels: []align(4) ashet.abi.ColorIndex,

    // Event handling:
    event_queue: astd.RingBuffer(ashet.abi.WindowEvent, event_queue_len) = .{},
    event_awaiter: ?*ashet.overlapped.AsyncCall = null,

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
            .pixels = undefined,
        };
        errdefer window.associated_memory.deinit();

        window.window_data = window.associated_memory.allocator().alignedAlloc(u8, 16, desktop.window_data_size) catch return error.SystemResources;
        @memset(window.window_data, 0);

        logger.info("create window ({},{})", .{
            window.max_size.width, window.max_size.height,
        });

        window.pixels = window.associated_memory.allocator().alignedAlloc(ashet.abi.ColorIndex, 4, @as(u32, window.max_size.width) * window.max_size.height) catch return error.SystemResources;

        window.title = window.associated_memory.allocator().dupeZ(u8, title) catch return error.SystemResources;

        desktop.windows.append(&window.desktop);
        errdefer desktop.windows.remove(&window.desktop);

        // Invoke the handler process:
        try desktop.notify_create_window(window);

        return window;
    }

    pub const destroy = Destructor.destroy;

    fn _notify_destroy(window: *Window) void {
        const desktop: *Desktop = window.desktop.data.desktop;

        // Invoke the handler process before removing it from the desktop.
        // this operation must happen as long as the window is still an "alive" resource:
        desktop.notify_destroy_window(window);

        desktop.windows.remove(&window.desktop);
    }

    fn _internal_destroy(window: *Window) void {
        const desktop: *Desktop = window.desktop.data.desktop;

        // The notification should have removed the window already from the desktop:
        std.debug.assert(!astd.is_in_linked_list(WindowDesktopLinkList, desktop.windows, &window.desktop));

        if (window.event_awaiter) |event_awaiter| {
            // If there's still an event awaiter for our window, we have to cancel the event,
            // as otherwise the awaiting process might be blocking forever.
            event_awaiter.finalize(ashet.abi.gui.GetWindowEvent, error.Cancelled);
        }

        ashet.memory.type_pool(Window).free(window);
    }

    pub fn post_event(window: *Window, event: ashet.abi.WindowEvent) void {
        if (window.event_queue.empty()) {
            // If the window event queue is empty, there are no pending events and we're the first
            // event to be pushed.
            if (window.event_awaiter) |event_awaiter| {
                // If that is the case, we can immediatly finish the awaiter
                // with the event we're handling.
                event_awaiter.finalize(ashet.abi.gui.GetWindowEvent, .{
                    .event = event,
                });
                window.event_awaiter = null;
                return;
            }
        } else {
            // Non-empty event queue means that there's definitly no one awaiting us
            // as otherwise events would've been pulled directly without setting the
            // awaiter state:
            std.debug.assert(window.event_awaiter == null);
        }

        if (window.event_queue.full()) {
            logger.warn("window event queue is full, dropping event {?}", .{window.event_queue.pull()});
        }
        window.event_queue.push(event);
    }
};

pub const Widget = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);
    system_resource: ashet.resources.SystemResource = .{ .type = .widget },

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(widget: *Widget) void {
        _ = widget;
        @panic("Not implemented yet!");
    }
};

pub const WidgetType = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);
    system_resource: ashet.resources.SystemResource = .{ .type = .widget_type },

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(widget_type: *WidgetType) void {
        _ = widget_type;
        @panic("Not implemented yet!");
    }
};

pub fn schedule_get_window_event(call: *ashet.overlapped.AsyncCall, inputs: ashet.abi.gui.GetWindowEvent.Inputs) void {
    const window: *Window = ashet.resources.resolve(Window, call.resource_owner, inputs.window.as_resource()) catch |err| {
        return call.finalize(ashet.abi.gui.GetWindowEvent, switch (err) {
            error.InvalidHandle, error.TypeMismatch => error.InvalidHandle,
        });
    };
    // If an awaiter is set, the event queue must be empty:
    defer if (window.event_awaiter != null)
        std.debug.assert(window.event_queue.empty());

    if (window.event_awaiter != null) {
        // We're having assigned an event awaiter.
        // This means there's no event yet that was completed, as otherwise it would've been
        // removed immediatly:
        std.debug.assert(window.event_queue.empty());
        return call.finalize(ashet.abi.gui.GetWindowEvent, error.InProgress);
    }

    if (window.event_queue.pull()) |ready_event| {
        // The event queue had an event for us, let's consume it and process it:
        return call.finalize(ashet.abi.gui.GetWindowEvent, .{
            .event = ready_event,
        });
    } else {
        // The event queue is empty and we don't have an event ready,
        // we have to await the event:
        std.debug.assert(window.event_awaiter == null);
        window.event_awaiter = call;
    }
}
