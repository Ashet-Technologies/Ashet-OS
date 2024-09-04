const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const abi = ashet.abi;
const syscalls = ashet.userland;

// Some imports:
const Point = ashet.abi.Point;
const Size = ashet.abi.Size;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;
const Color = ashet.abi.Color;

// Application logic:

const WindowList = std.DoublyLinkedList(void);
const WindowNode = WindowList.Node;

var active_windows: WindowList = .{};

pub fn main() !void {
    std.log.info("classic desktop startup...", .{});
    const video_output = try syscalls.video.acquire(.primary);
    defer video_output.release();

    const screen_size = try syscalls.video.get_resolution(video_output);

    std.log.info("primary video output has a resolution of {}x{}", .{
        screen_size.width,
        screen_size.height,
    });

    const vmem = try syscalls.video.get_video_memory(video_output);

    std.log.info("video memory: base=0x{X:0>8}, stride={}, width={}, height={}", .{
        @intFromPtr(vmem.base),
        vmem.stride,
        vmem.width,
        vmem.height,
    });

    // Load nice pattern:
    var scanline: [*]abi.ColorIndex = vmem.base;
    for (0..vmem.height) |y| {
        for (scanline[0..vmem.width], 0..) |*pixel, x| {
            pixel.* = @enumFromInt(@as(u4, @truncate(x ^ y)));
        }
        scanline += vmem.stride;
    }

    // Let the rest of the system continue to boot:
    syscalls.process.thread.yield();

    const desktop = try syscalls.gui.create_desktop("Classic", &.{
        .window_data_size = @sizeOf(WindowData),
        .handle_event = handle_desktop_event,
    });
    defer desktop.release();

    const apps_dir = try ashet.overlapped.performOne(abi.fs.OpenDrive, .{
        .fs = .system,
        .path_ptr = "apps",
        .path_len = 4,
    });
    defer apps_dir.dir.release();

    const desktop_proc = try ashet.overlapped.performOne(abi.process.Spawn, .{
        .dir = apps_dir.dir,
        .path_ptr = "hello-gui/code",
        .path_len = 14,
        .argv_ptr = &[_]abi.SpawnProcessArg{
            abi.SpawnProcessArg.string("--desktop"),
            abi.SpawnProcessArg.resource(desktop.as_resource()),
        },
        .argv_len = 2,
    });
    desktop_proc.process.release(); // we're not interested in "holding" onto process

    while (true) {
        // TODO: Can we suspend this thread and just react to the desktop events
        //       in the callback context?
        //       Long running event handlers like message boxes should probably run
        //       inside the main thread here?
        ashet.process.thread.yield();
    }
}

fn handle_desktop_event(desktop: abi.Desktop, event: *const abi.DesktopEvent) callconv(.C) void {
    std.log.debug("handle desktop event of type {s}", .{@tagName(event.event_type)});
    switch (event.event_type) {
        .create_window => {
            const window = event.create_window.window;
            std.log.info("handle_desktop_event.create_window({})", .{window});

            const data = WindowData.from_handle(window);
            active_windows.append(&data.window_node);

            // TODO: Set up basic structure

            // TODO: Redraw invalidated desktop region
        },

        .destroy_window => {
            const window = event.create_window.window;
            std.log.info("handle_desktop_event.destroy_window({})", .{window});

            const data = WindowData.from_handle(window);
            active_windows.remove(&data.window_node);

            // TODO: Redraw invalidated desktop region
        },

        .show_message_box => {
            std.log.info("handle_desktop_event.show_message_box(request_id=0x{X:0>4}, caption='{}', message='{}', icon={s}, buttons='{}')", .{
                @intFromEnum(event.show_message_box.request_id),
                std.zig.fmtEscapes(event.show_message_box.caption()),
                std.zig.fmtEscapes(event.show_message_box.message()),
                @tagName(event.show_message_box.icon),
                event.show_message_box.buttons,
            });

            // TODO: Implement message boxes
        },

        .show_notification => {
            std.log.info("handle_desktop_event.show_notification(message='{}', severity={s})", .{
                std.zig.fmtEscapes(event.show_notification.message()),
                @tagName(event.show_notification.severity),
            });

            // TODO: Implement notifications
        },

        _ => {
            std.log.info("handle_desktop_event(invalid event: {d})", .{@intFromEnum(event.event_type)});
        },
    }

    _ = desktop;
}

const WindowData = struct {
    window_node: WindowNode = .{ .data = {} },

    pub fn from_handle(handle: ashet.abi.Window) *WindowData {
        return @ptrCast(
            syscalls.gui.get_desktop_data(handle) catch @panic("kernel bug"),
        );
    }
};
