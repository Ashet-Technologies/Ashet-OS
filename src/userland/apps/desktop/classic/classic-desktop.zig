const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const abi = ashet.abi_v2;
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

    std.log.info("video memory resides at 0x{X:0>8}", .{@intFromPtr(vmem)});

    while (true) {
        //

        syscalls.process.thread.yield();
    }

    // const desktop = try syscalls.gui.create_desktop("Classic", &.{
    //     .window_data_size = @sizeOf(WindowData),
    //     .handle_event = handle_desktop_event,
    // });
    // defer desktop.release();
}

// fn handle_desktop_event(desktop: abi.Desktop, event: *const abi.DesktopEvent) callconv(.C) void {
//     //
//     _ = desktop;
//     _ = event;
// }

// const WindowData = struct {
//     //
// };
