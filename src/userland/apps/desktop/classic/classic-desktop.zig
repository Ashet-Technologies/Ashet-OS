const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const abi = ashet.abi_v2;
const syscalls = ashet.userland.syscalls;

pub fn main() !void {
    const desktop = try syscalls.gui.create_desktop("Classic", &.{
        .window_data_size = @sizeOf(WindowData),
        .handle_event = handle_desktop_event,
    });
    defer desktop.release();
}

fn handle_desktop_event(desktop: abi.Desktop, event: *const abi.DesktopEvent) callconv(.C) void {
    //
    _ = desktop;
    _ = event;
}

const WindowData = struct {
    //
};
