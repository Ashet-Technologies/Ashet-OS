const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../libashet.zig");
const logger = std.log.scoped(.gui);

const Size = ashet.abi.Size;
const Point = ashet.abi.Point;
const Rectangle = ashet.abi.Rectangle;

pub const UUID = ashet.abi.UUID;

pub const Desktop = ashet.abi.Desktop;
pub const Window = ashet.abi.Window;
pub const Widget = ashet.abi.Widget;
pub const WidgetType = ashet.abi.WidgetType;

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

pub fn create_widget(window: Window, uuid: *const UUID) !Widget {
    return try ashet.abi.gui.create_widget(window, uuid);
}

pub fn place_widget(widget: Widget, bounds: Rectangle) !Rectangle {
    return try ashet.abi.gui.place_widget(widget, bounds);
}

pub const widgets = struct {
    pub const label = UUID.constant("53b8be36-969a-46a3-bdf5-e3d197890219");

    pub const button = UUID.constant("782ccd0e-bae4-4093-93fe-12c1f86ff43c");

    pub const panel = UUID.constant("1fa5b237-0bda-48d1-b95a-fcf80616318b");

    pub const picture_box = UUID.constant("bb33e7a1-74ad-4040-a248-0015ba6b9dac");

    pub const progress_bar = UUID.constant("b96290a9-542f-45f5-9e37-1ce9084fc0e3");

    pub const group_box = UUID.constant("b96bc6a2-6df0-4f76-962a-4af18fdf3548");

    pub const text_box = UUID.constant("02eddbc3-b882-41e9-8aba-10d12b451e11");

    pub const multi_line_text_box = UUID.constant("84d40a1a-04ab-4e00-ae93-6e91e6b3d10a");

    pub const vertical_scroll_bar = UUID.constant("d1c52f74-e9b8-4067-8bb6-fe01c49d97ae");

    pub const horizontal_scroll_bar = UUID.constant("2899397f-ede2-46e9-8458-1eea29c81fa1");

    pub const check_box = UUID.constant("051c6bff-d491-4e5a-8b77-6f4244da52ee");

    pub const radio_button = UUID.constant("4f18fde6-944c-494f-a55c-ba11f45fcfa3");
};
