const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../libashet.zig");
const logger = std.log.scoped(.gui);

const Size = ashet.abi.Size;

pub const Desktop = ashet.abi.Desktop;
pub const Window = ashet.abi.Window;
pub const Widget = ashet.abi.Widget;

pub const WindowFlags = ashet.abi.WindowFlags;
pub const WidgetNotifyEvent = ashet.abi.WidgetNotifyEvent;
pub const KeyboardEvent = ashet.abi.KeyboardEvent;
pub const MouseEvent = ashet.abi.MouseEvent;

pub const GetWindowEvent = ashet.abi.gui.GetWindowEvent;

pub fn get_desktop_data(window: Window) error{ InvalidHandle, Unexpected }!*anyopaque {
    return try ashet.abi.gui.get_desktop_data(window);
}

pub fn post_window_event(window: Window, event: ashet.abi.WindowEvent) !void {
    try ashet.abi.gui.post_window_event(window, event);
}

pub const CreateWindowOptions = struct {
    min_size: Size,
    max_size: Size,
    initial_size: Size,
    title: []const u8,
    popup: bool = false,
};

pub const DesktopCreateOptions = ashet.abi.DesktopDescriptor;

pub fn create_desktop(name: []const u8, options: DesktopCreateOptions) !ashet.abi.Desktop {
    return try ashet.abi.gui.create_desktop(name, &options);
}

pub fn create_window(desktop: Desktop, options: CreateWindowOptions) !ashet.abi.Window {
    return try ashet.abi.gui.create_window(
        desktop,
        options.title,
        options.min_size,
        options.max_size,
        options.initial_size,
        .{
            .popup = options.popup,
        },
    );
}

pub fn get_window_title(window: Window, buffer: ?[]u8) error{ InvalidHandle, Unexpected }!usize {
    return try ashet.abi.gui.get_window_title(window, buffer);
}

pub fn get_window_size(window: Window) error{ InvalidHandle, Unexpected }!Size {
    return try ashet.abi.gui.get_window_size(window);
}

pub fn get_window_min_size(window: Window) error{ InvalidHandle, Unexpected }!Size {
    return try ashet.abi.gui.get_window_min_size(window);
}

pub fn get_window_max_size(window: Window) error{ InvalidHandle, Unexpected }!Size {
    return try ashet.abi.gui.get_window_max_size(window);
}

pub fn get_window_flags(window: Window) error{ InvalidHandle, Unexpected }!WindowFlags {
    return try ashet.abi.gui.get_window_flags(window);
}

pub fn set_window_size(window: Window, size: Size) error{ InvalidHandle, Unexpected }!Size {
    return try ashet.abi.gui.set_window_size(window, size);
}

pub fn get_window_event(window: Window) error{ Unexpected, InvalidHandle, SystemResources, Cancelled, InProgress }!WindowEvent {
    const event_res = try ashet.overlapped.performOne(ashet.abi.gui.GetWindowEvent, .{
        .window = window,
    });
    return .from_abi(event_res.event);
}

pub const WindowEvent = union(ashet.abi.WindowEvent.Type) {
    widget_notify: WidgetNotifyEvent,
    key_press: KeyboardEvent,
    key_release: KeyboardEvent,
    mouse_enter: MouseEvent,
    mouse_leave: MouseEvent,
    mouse_motion: MouseEvent,
    mouse_button_press: MouseEvent,
    mouse_button_release: MouseEvent,
    window_close,
    window_minimize,
    window_restore,
    window_moving,
    window_moved,
    window_resizing,
    window_resized,

    pub fn from_abi(event: ashet.abi.WindowEvent) WindowEvent {
        return ashet.utility.wrap_abi_union(WindowEvent, event, .{
            .widget_notify = .widget_notify,
            .key_press = .keyboard,
            .key_release = .keyboard,
            .mouse_enter = .mouse,
            .mouse_leave = .mouse,
            .mouse_motion = .mouse,
            .mouse_button_press = .mouse,
            .mouse_button_release = .mouse,
            .window_close = null,
            .window_minimize = null,
            .window_restore = null,
            .window_moving = null,
            .window_moved = null,
            .window_resizing = null,
            .window_resized = null,
        });
    }
};
