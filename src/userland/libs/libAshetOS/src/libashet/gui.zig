const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../libashet.zig");
const logger = std.log.scoped(.gui);

const Size = ashet.abi.Size;

pub const Desktop = ashet.abi.Desktop;
pub const Window = ashet.abi.Window;
pub const Widget = ashet.abi.Widget;

pub fn get_desktop_data(window: Window) error{ InvalidHandle, Unexpected }!*anyopaque {
    return try ashet.userland.gui.get_desktop_data(window);
}

pub fn post_window_event(window: Window, event: ashet.abi.WindowEvent) !void {
    try ashet.userland.gui.post_window_event(window, event);
}

pub const CreateWindowOptions = struct {
    min_size: Size,
    max_size: Size,
    initial_size: Size,
    title: []const u8,
    popup: bool = false,
};

pub fn create_window(desktop: Desktop, options: CreateWindowOptions) !ashet.abi.Window {
    return try ashet.userland.gui.create_window(
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

pub fn get_window_title(window: Window) error{ InvalidHandle, Unexpected }![]const u8 {
    var title: []const u8 = undefined;
    try ashet.userland.gui.get_window_title(window, &title);
    return title;
}

pub fn get_window_size(window: Window) error{ InvalidHandle, Unexpected }!Size {
    return try ashet.userland.gui.get_window_size(window);
}

pub fn get_window_min_size(window: Window) error{ InvalidHandle, Unexpected }!Size {
    return try ashet.userland.gui.get_window_min_size(window);
}

pub fn get_window_max_size(window: Window) error{ InvalidHandle, Unexpected }!Size {
    return try ashet.userland.gui.get_window_max_size(window);
}

pub fn get_window_flags(window: Window) error{ InvalidHandle, Unexpected }!ashet.abi.CreateWindowFlags {
    return try ashet.userland.gui.get_window_flags(window);
}

pub fn set_window_size(window: Window, size: Size) error{ InvalidHandle, Unexpected }!Size {
    return try ashet.userland.gui.set_window_size(window, size);
}
