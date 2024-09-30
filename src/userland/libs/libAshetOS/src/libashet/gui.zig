const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../libashet.zig");
const logger = std.log.scoped(.gui);

pub const Window = ashet.abi.Window;

pub fn get_desktop_data(window: Window) error{ InvalidHandle, Unexpected }!*anyopaque {
    return try ashet.userland.gui.get_desktop_data(window);
}

pub fn post_window_event(window: Window, event: ashet.abi.WindowEvent) !void {
    try ashet.userland.gui.post_window_event(window, event);
}
