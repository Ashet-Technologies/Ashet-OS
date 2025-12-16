const std = @import("std");
const astd = @import("ashet-std");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.gui);

const Point = ashet.abi.Point;
const Size = ashet.abi.Size;
const Rectangle = ashet.abi.Rectangle;
const CreateWindowFlags = ashet.abi.CreateWindowFlags;

const UUID = ashet.abi.UUID;

const WindowDesktopLink = struct {
    desktop: *Desktop,
};
const WindowDesktopLinkList = astd.DoublyLinkedList(WindowDesktopLink, .{});
const WindowDesktopLinkNode = WindowDesktopLinkList.Node;

const DesktopList = astd.DoublyLinkedList(void, .{ .tag = opaque {} });
const WidgetList = astd.DoublyLinkedList(void, .{ .tag = opaque {} });

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

    fn notify_invalidate_window(desktop: *Desktop, window: *Window, area: Rectangle) void {
        const window_handle = ashet.resources.get_handle(desktop.server_process, &window.system_resource) orelse {
            logger.warn("failed to send notify_invalidate_window notification: window does not exist anymore!", .{});
            return;
        };
        desktop.process_event(.{
            .invalidate_window = .{
                .event_type = .invalidate_window,
                .window = window_handle.unsafe_cast(.window),
                .area = area,
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
    pixels: []align(4) ashet.abi.Color,

    // Event handling:
    event_queue: astd.RingBuffer(ashet.abi.WindowEvent, event_queue_len) = .{},
    event_awaiter: ?*ashet.overlapped.AsyncCall = null,

    // Widget management:

    /// The list of all active widgets for this window.
    /// `.first` refers to the bottom widget,
    /// `.last` refers to the top widget.
    widgets: WidgetList = .empty,

    /// The widget which currently has keyboard focus
    focused_widget: ?*Widget = null,

    /// The widget which is currently hovered by the mouse
    hovered_widget: ?*Widget = null,

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

        window.pixels = window.associated_memory.allocator().alignedAlloc(ashet.abi.Color, 4, @as(u32, window.max_size.width) * window.max_size.height) catch return error.SystemResources;
        @memset(window.pixels, .from_hsv(.purple, 1, 1)); // TODO: Set obnoxious color here to force a default or allow passing a default via window parameters

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

        while (window.widgets.last) |tail_widget| {
            const widget: *Widget = Widget.from_link(tail_widget);
            std.debug.assert(widget.window == window);

            widget.destroy();

            // destroy must remove the widget from the list of widgets inside
            // this window, so we add a safety check for this:
            std.debug.assert(!window.widgets.contains(tail_widget));
        }

        // Invoke the handler process before removing it from the desktop.
        // this operation must happen as long as the window is still an "alive" resource:
        desktop.notify_destroy_window(window);

        desktop.windows.remove(&window.desktop);
    }

    fn _internal_destroy(window: *Window) void {
        const desktop: *Desktop = window.desktop.data.desktop;

        // The notification should have removed the window already from the desktop:
        std.debug.assert(!desktop.windows.contains(&window.desktop));

        if (window.event_awaiter) |event_awaiter| {
            // If there's still an event awaiter for our window, we have to cancel the event,
            // as otherwise the awaiting process might be blocking forever.
            event_awaiter.finalize(ashet.abi.gui.GetWindowEvent, error.Cancelled);
        }

        ashet.memory.type_pool(Window).free(window);
    }

    /// Invalidates the complete window and notifies the owning desktop that it should handle this.
    pub fn invalidate_full(window: *Window) void {
        window.invalidate_region(.new(
            Point.zero,
            window.size,
        ));
    }

    /// Invalidates a region of the window and notifies the owning desktop that this part should be drawn.
    pub fn invalidate_region(window: *Window, region: Rectangle) void {
        const desktop: *Desktop = window.desktop.data.desktop;
        desktop.notify_invalidate_window(window, region);
    }

    ///
    /// Posts an event to the window.
    ///
    /// If the event affects a widget, the widget will process the event. If no widget is suitable
    /// to handle the event, the event will be posted into the window event queue.
    ///
    /// NOTE: This function finalizes the GetWindowEvent awaiter.
    ///
    pub fn post_event(window: *Window, event: ashet.abi.WindowEvent) void {

        // TODO: Implement ".click" widget event.
        //       This event is a bit more tricky as it needs tracking which widget was clicked.
        //       A click with the mouse is valid when, and only when:
        //         mouse_button_down and mouse_button_up with the left mouse button happen on the
        //         same widget. The hovered widget *may* change in between the mouse down and mouse up,
        //         but the click will still be recognized.
        //       A click with the keyboard is valid when, and only when:
        //         key_press and key_release happen without changing the focused widget, and only when
        //         space or return key were pressed without any other key interrupting.

        // TODO: Implement the ".scroll" widget event
        //       This is probably best done by removing scroll buttons from the mouse_button_press, mouse_button_release event
        //       and implement it as a separate axis (scroll_h, scroll_v).
        //

        switch (event.event_type) {

            // This event is generated by widgets, so it's forwarded:
            .widget_notify => {},

            // Keyboard events go through the focused widget (if any):
            .key_press, .key_release => if (window.focused_widget) |widget| {
                // Focused widgets just receive the keyboard event,
                // and the window won't see them:
                widget.process_event(.{
                    .keyboard = .{
                        .event_type = .{ .widget = switch (event.event_type) {
                            .key_press => .key_press,
                            .key_release => .key_release,
                            else => unreachable,
                        } },
                        .usage = event.keyboard.usage,
                        .text_ptr = event.keyboard.text_ptr,
                        .text_len = event.keyboard.text_len,
                        .pressed = event.keyboard.pressed,
                        .modifiers = event.keyboard.modifiers,
                    },
                });
                return;
            },

            // Mouse input events must be forwarded to the widgets:
            .mouse_motion,
            .mouse_button_press,
            .mouse_button_release,
            => {
                const pos: Point = .new(event.mouse.x, event.mouse.y);

                // Get the widget from the mouse position, and update the hovered state.
                // This must be done through the function as we have to inform both previous
                // and new widget about the state change:
                const maybe_hovered_widget: ?*Widget = window.widget_from_pos(pos);
                window.update_hovered_widget(maybe_hovered_widget, event.mouse);
                std.debug.assert(window.hovered_widget == maybe_hovered_widget);

                if (event.event_type == .mouse_button_press and event.mouse.button == .left) {
                    if (maybe_hovered_widget) |widget| {
                        if (widget.type.flags.focusable) {
                            window.update_focused_widget(widget);
                        }
                    } else {
                        window.update_focused_widget(null);
                    }
                }

                if (maybe_hovered_widget) |widget| {
                    // If we have a widget, the event will be forwarded to the
                    // widget server and won't show up in the window queue:
                    widget.process_event(derive_mouse_event(widget, event.mouse, switch (event.event_type) {
                        .mouse_motion => .mouse_motion,
                        .mouse_button_press => .mouse_button_press,
                        .mouse_button_release => .mouse_button_release,
                        else => unreachable,
                    }));
                    return;
                }
            },

            // Mouse enter isn't relevant for widget management
            .mouse_enter => {},

            // but mouse_leave must set the hovered widget to null, and
            // optionally send the correct widget event:
            .mouse_leave => window.update_hovered_widget(null, event.mouse),

            // Window events affect the window directly and won't be noticed
            // at all by widgets:
            .window_close,
            .window_minimize,
            .window_restore,
            .window_moving,
            .window_moved,
            .window_resizing,
            .window_resized,
            => {},
        }

        window.post_event_direct(event);
    }

    fn update_focused_widget(window: *Window, maybe_new_widget: ?*Widget) void {
        if (maybe_new_widget) |new_widget| {
            if (!new_widget.type.flags.focusable)
                return;
        }

        const maybe_old_widget: ?*Widget = window.focused_widget;
        if (maybe_old_widget == maybe_new_widget)
            return;

        if (maybe_old_widget) |old_widget| {
            old_widget.process_event(.{
                .event_type = .focus_leave,
            });
        }

        window.focused_widget = maybe_new_widget;

        if (maybe_new_widget) |new_widget| {
            new_widget.process_event(.{
                .event_type = .focus_enter,
            });
        }
    }

    fn update_hovered_widget(window: *Window, maybe_new_widget: ?*Widget, mouse_event: ashet.abi.MouseEvent) void {
        const maybe_old_widget: ?*Widget = window.hovered_widget;
        if (maybe_old_widget != maybe_new_widget) {
            // We have detected a change of focus. The mouse hovered
            // a different widget previously.

            if (maybe_old_widget) |old_widget| {
                old_widget.process_event(
                    derive_mouse_event(old_widget, mouse_event, .mouse_leave),
                );
            }
            if (maybe_new_widget) |new_widget| {
                new_widget.process_event(
                    derive_mouse_event(new_widget, mouse_event, .mouse_enter),
                );
            }
        }
        window.hovered_widget = maybe_new_widget;
    }

    /// Derives a new Widget mouse event from a window mouse event.
    /// This changes the type of the event and adjusts the (x,y) position relative to the widget position.
    fn derive_mouse_event(widget: *Widget, mouse_event: ashet.abi.MouseEvent, event_type: ashet.abi.WidgetEvent.Type) ashet.abi.WidgetEvent {
        var evt = mouse_event;
        evt.event_type = .{ .widget = event_type };
        evt.x -|= widget.bounds.x;
        evt.y -|= widget.bounds.y;
        return .{ .mouse = evt };
    }

    /// Gets a widget from the given position.
    fn widget_from_pos(window: *Window, pos: Point) ?*Widget {
        // Iterate top-to-bottom so we get the uppermost widget first:
        var iter = window.widgets.last;
        while (iter) |node| : (iter = node.prev) {
            const widget = Widget.from_link(node);

            if (!widget.type.flags.hit_test_visible)
                continue;

            if (widget.bounds.contains(pos))
                return widget;
        }
        return null;
    }

    ///
    /// Posts an event directly into the window event queue and finalizes the GetWindowEvent awaiter.
    ///
    /// NOTE: This function bypasses any widget handling!
    pub fn post_event_direct(window: *Window, event: ashet.abi.WindowEvent) void {
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
    pub const Destructor = ashet.resources.DestructorWithNotification(@This(), _internal_destroy, _notify_destroy);

    // static data
    system_resource: ashet.resources.SystemResource = .{ .type = .widget },
    associated_memory: std.heap.ArenaAllocator,
    type: *WidgetType,

    // window integration
    window: *Window,
    window_link: WidgetList.Node = .{ .data = {} },

    // visuals
    bounds: Rectangle,
    pixels: []align(4) ashet.abi.Color,

    // type-specific data
    widget_data: []u8,

    pub const destroy = Destructor.destroy;

    pub fn create(
        owner: *Window,
        uuid: *const UUID,
    ) error{ SystemResources, WidgetNotFound }!*Widget {
        const widget_type = WidgetType.registry.get(uuid.*) orelse return error.WidgetNotFound;

        const widget = ashet.memory.type_pool(Widget).alloc() catch return error.SystemResources;
        errdefer ashet.memory.type_pool(Widget).free(widget);

        widget.* = .{
            .associated_memory = std.heap.ArenaAllocator.init(ashet.memory.allocator),
            .window = owner,
            .type = widget_type,

            .bounds = .{ .x = 0, .y = 0, .width = 0, .height = 0 },

            .pixels = undefined,
            .widget_data = undefined,
        };
        errdefer widget.associated_memory.deinit();

        widget.widget_data = widget.associated_memory.allocator().alignedAlloc(u8, 16, widget_type.widget_data_size) catch return error.SystemResources;
        @memset(widget.widget_data, 0);

        widget.pixels = widget.associated_memory.allocator().alignedAlloc(ashet.abi.Color, 4, 0) catch return error.SystemResources;

        owner.widgets.append(&widget.window_link);
        errdefer owner.widgets.remove(&widget.window_link);

        try widget.type.process_event(widget, .add_ownership, .{
            .event_type = .create,
        });

        return widget;
    }

    pub fn from_link(link: *WidgetList.Node) *Widget {
        return @fieldParentPtr("window_link", link);
    }

    fn _notify_destroy(widget: *Widget) void {
        if (widget.window.focused_widget == widget) {
            widget.window.update_focused_widget(null);
        }

        widget.type.process_event(widget, .default, .{
            .event_type = .destroy,
        });

        widget.window.widgets.remove(&widget.window_link);
    }

    fn _internal_destroy(widget: *Widget) void {
        std.debug.assert(!widget.window.widgets.contains(&widget.window_link));

        widget.associated_memory.deinit();
        ashet.memory.type_pool(Widget).free(widget);
    }

    /// Processes the event with default handling.
    ///
    /// Forwards the call to `widget.type.process_event` with `.default` mode,
    /// so the widget won't be created inside the widget server process.
    pub fn process_event(widget: *Widget, event: ashet.abi.WidgetEvent) void {
        widget.type.process_event(widget, .default, event);
    }

    /// Sends the "control" event to the widget.
    ///
    /// NOTE: This function patches the `message.event_type` field to `.control` before forwarding it.
    pub fn control(widget: *Widget, message: ashet.abi.WidgetControlMessage) void {
        var msg = message;
        msg.event_type = .control;
        widget.process_event(.{ .control = msg });
    }

    /// Puts `event` into its window event queue.
    ///
    /// NOTE: This function patches `event.event_type` to `.widget_notify` before passing it to the event queue.
    pub fn notify_owner(widget: *Widget, event: ashet.abi.WidgetNotifyEvent) void {
        var evt = event;
        evt.event_type = .widget_notify;
        widget.window.post_event_direct(.{
            .widget_notify = evt,
        });
    }

    /// Places the widget into a new location on the owning window.
    /// Invokes the widget server and emits necessary resize events.
    ///
    /// Returns the new actual location of the widget.
    pub fn place(widget: *Widget, desired_bounds: Rectangle) Rectangle {
        const previous = widget.bounds;

        const resize_requested = !previous.size().eql(desired_bounds.size());

        widget.bounds = desired_bounds;
        if (resize_requested) {
            widget.process_event(.{
                .event_type = .resized,
            });
        }

        const resize_granted = resize_requested and !previous.size().eql(widget.bounds.size());

        const was_moved = !previous.position().eql(desired_bounds.position());

        logger.info("{*} resized from {} to {}", .{ widget, previous, widget.bounds });

        if (resize_granted) {
            // Resize the internal pixel buffer to new size:
            const allocator = widget.associated_memory.allocator();

            const new_size = @as(usize, widget.bounds.width) * @as(usize, widget.bounds.height);
            if (widget.pixels.len < new_size) {
                // we don't have enough storage for the new resized widget,
                // so we have to get more memory:
                if (!allocator.resize(widget.pixels, new_size)) {
                    if (allocator.realloc(widget.pixels, new_size)) |new_pixels| {
                        widget.pixels = new_pixels;
                    } else |_| {
                        // we failed to reallocate the new pixel buffer.
                        // this means the resize operation is failing as it
                        // would out of memory. to prevent a crash, just accept
                        // that the resize can't happen right now and revert it.

                        logger.err("failed to resize widget {*} from {} to {}: out of memory", .{
                            widget,
                            previous.size(),
                            widget.bounds.size(),
                        });

                        widget.bounds.width = previous.width;
                        widget.bounds.height = previous.height;
                    }
                }
            }
        }
        const was_resized = !previous.size().eql(widget.bounds.size());

        if (was_resized) {
            // the widget was resized, which means its pixel contents aren't correctly rendered
            // anymore.
            @memset(widget.pixels, .black);
            widget.process_event(.{
                // TODO: Rendering is asynchronous, how can we handle this here?
                //       the paint even must be processed synchronously, but the rendering
                //       can take some time and might conflict with other schedulings.
                .event_type = .paint,
            });
        }

        if (was_moved) {
            // If we moved the widget, we have to invalidate both the previous and the new
            // location:
            widget.window.invalidate_region(previous);
            widget.window.invalidate_region(widget.bounds);
        } else if (was_resized) {
            // If we only resized the widget, we can just invalidate the bigger of the two
            // areas
            std.debug.assert(widget.bounds.x == previous.x);
            std.debug.assert(widget.bounds.y == previous.y);
            widget.window.invalidate_region(.{
                .x = widget.bounds.x,
                .y = widget.bounds.y,
                .width = @max(widget.bounds.width, previous.width),
                .height = @max(widget.bounds.height, previous.height),
            });
        } else {
            std.debug.assert(widget.bounds.eql(previous));
        }

        return widget.bounds;
    }
};

pub const WidgetType = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);

    pub var registry: std.AutoArrayHashMapUnmanaged(UUID, *WidgetType) = .empty;

    system_resource: ashet.resources.SystemResource = .{ .type = .widget_type },
    server_process: *ashet.multi_tasking.Process,

    uuid: UUID,
    widget_data_size: usize,
    flags: ashet.abi.WidgetDescriptor.Flags,
    handle_event: ashet.abi.WidgetEventHandler,

    pub const destroy = Destructor.destroy;

    pub fn create(
        server_process: *ashet.multi_tasking.Process,
        descriptor: *const ashet.abi.WidgetDescriptor,
    ) error{ SystemResources, AlreadyRegistered }!*WidgetType {
        const gop = registry.getOrPut(ashet.memory.allocator, descriptor.uuid) catch |err| switch (err) {
            error.OutOfMemory => return error.SystemResources,
        };
        if (gop.found_existing)
            return error.AlreadyRegistered;
        errdefer _ = registry.swapRemove(descriptor.uuid);

        const widget_type = ashet.memory.type_pool(WidgetType).alloc() catch return error.SystemResources;
        errdefer ashet.memory.type_pool(WidgetType).free(widget_type);

        widget_type.* = .{
            .server_process = server_process,
            .uuid = descriptor.uuid,
            .widget_data_size = descriptor.data_size,
            .flags = descriptor.flags,
            .handle_event = descriptor.handle_event,
        };

        gop.value_ptr.* = widget_type;

        return widget_type;
    }

    fn _internal_destroy(widget_type: *WidgetType) void {
        // TODO: Assert that no widgets of this type exist anymore / kill these widgets

        // Removal of the registry must succeed, as otherwise
        // we have a double-free situation or another registry corruption.
        std.debug.assert(registry.swapRemove(widget_type.uuid));

        ashet.memory.type_pool(WidgetType).free(widget_type);
    }

    const ProcessEventMode = enum { default, add_ownership };

    pub fn process_event(widget_type: *WidgetType, widget: *Widget, comptime mode: ProcessEventMode, event: ashet.abi.WidgetEvent) switch (mode) {
        .default => void,
        .add_ownership => error{SystemResources}!void,
    } {
        const type_handle = ashet.resources.get_handle(widget_type.server_process, &widget_type.system_resource) orelse @panic("process_event called for a process that does not own the widget type");

        const widget_handle = switch (mode) {
            .add_ownership => try ashet.resources.add_to_process(widget_type.server_process, &widget.system_resource),
            .default => ashet.resources.get_handle(widget_type.server_process, &widget.system_resource) orelse {
                logger.warn("failed to process widget notification: widget does not exist anymore!", .{});
                return;
            },
        };

        ashet.multi_tasking.call_inside_process(
            widget_type.server_process,
            widget_type.handle_event,
            .{
                type_handle.unsafe_cast(.widget_type),
                widget_handle.unsafe_cast(.widget),
                &event,
            },
        );
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
