const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const abi = ashet.abi;
const syscalls = ashet.userland;

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
    std.log.info("handle desktop event of type {}", .{event.event_type});

    _ = desktop;
}

const WindowData = struct {
    //
};
