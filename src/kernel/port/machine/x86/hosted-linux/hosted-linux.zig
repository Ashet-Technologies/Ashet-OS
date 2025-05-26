//!
//! Hosted Linux PC
//!

const std = @import("std");
const ashet = @import("../../../../main.zig");
const hosted = @import("../../../hosted/initialize.zig");

const logger = std.log.scoped(.@"hosted-linux");

const Wayland_Display = @import("Wayland_Display.zig");
const X11_Display = @import("X11_Display.zig");

const mprotect = @import("mprotect.zig");

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = false, .bss = false },
    .memory_protection = .{
        .initialize = mprotect.initialize,
        .update = mprotect.update,
        .activate = mprotect.activate,
        .get_protection = mprotect.get_protection,
        .get_info = mprotect.query_address,
    },
    .initialize = initialize,
    .early_initialize = null,
    .debug_write = hosted.debug_write,
    .get_linear_memory_region = hosted.get_linear_memory_region,
    .get_tick_count_ms = hosted.get_tick_count_ms,
};

fn initialize() !void {
    {
        const linear_memory = hosted.get_linear_memory_region();
        const res = std.os.linux.mprotect(
            @ptrFromInt(linear_memory.base),
            linear_memory.length,
            std.os.linux.PROT.EXEC | std.os.linux.PROT.READ | std.os.linux.PROT.WRITE,
        );
        if (res != 0) @panic("mprotect failed!");
    }

    try hosted.initialize(video_drivers);
}

const video_drivers: std.StaticStringMap(hosted.VideoDriverCtor) = .initComptime(.{
    .{ "x11", video_drivers_ctors.x11 },
    .{ "wayland", video_drivers_ctors.wayland },
    .{ "auto-window", video_drivers_ctors.auto },
});

const video_drivers_ctors = struct {
    fn x11(options: hosted.VideoDriverOptions) !void { // "video:x11:<width>:<height>"

        if (X11_Display.init(
            hosted.global_memory,
            options.video_out_index,
            options.res_x,
            options.res_y,
        )) |display| {
            ashet.drivers.install(&display.screen.driver);

            const thread = try ashet.scheduler.Thread.spawn(X11_Display.process_events_wrapper, display, .{
                .stack_size = 1024 * 1024,
            });
            try thread.setName("x11.eventloop");
            try thread.start();
            thread.detach();
        } else |err| switch (err) {
            // error.NoWaylandSupport => {
            //     @panic("Could not find Wayland socket!");
            // },
            else => |e| return e,
        }
    }
    fn wayland(options: hosted.VideoDriverOptions) !void {
        // "video:wayland:<width>:<height>"

        if (Wayland_Display.init(
            hosted.global_memory,
            options.video_out_index,
            options.res_x,
            options.res_y,
        )) |display| {
            ashet.drivers.install(&display.screen.driver);

            const thread = try ashet.scheduler.Thread.spawn(Wayland_Display.process_events_wrapper, display, .{
                .stack_size = 1024 * 1024,
            });
            try thread.setName("wayland.eventloop");
            try thread.start();
            thread.detach();
        } else |err| switch (err) {
            error.NoWaylandSupport => {
                @panic("Could not find Wayland socket!");
            },
            else => |e| return e,
        }
    }
    fn auto(options: hosted.VideoDriverOptions) !void {
        if (Wayland_Display.init(
            hosted.global_memory,
            options.video_out_index,
            options.res_x,
            options.res_y,
        )) |display| {
            ashet.drivers.install(&display.screen.driver);

            const thread = try ashet.scheduler.Thread.spawn(Wayland_Display.process_events_wrapper, display, .{
                .stack_size = 1024 * 1024,
            });
            try thread.setName("wayland.eventloop");
            try thread.start();
            thread.detach();
        } else |err| switch (err) {
            error.NoWaylandSupport => {
                const display = try X11_Display.init(
                    hosted.global_memory,
                    options.video_out_index,
                    options.res_x,
                    options.res_y,
                );

                ashet.drivers.install(&display.screen.driver);

                const thread = try ashet.scheduler.Thread.spawn(X11_Display.process_events_wrapper, display, .{
                    .stack_size = 1024 * 1024,
                });
                try thread.setName("x11.eventloop");
                try thread.start();
                thread.detach();
            },
            else => |e| return e,
        }
    }
};

// extern const __machine_linmem_start: u8 align(4);
// extern const __machine_linmem_end: u8 align(4);

comptime {
    // Provide some global symbols.
    // We can fake the {flash,data,bss}_{start,end} symbols,
    // as we know that these won't overlap with linmem anyways:
    asm (
        \\
        \\.global __kernel_stack_start
        \\.global __kernel_stack_end
        \\__kernel_stack_start:
        \\.space 8 * 1024 * 1024        # 8 MB of stack
        \\__kernel_stack_end:
        \\
        \\.align 4096
        \\__kernel_flash_start:
        \\__kernel_flash_end:
        \\__kernel_data_start:
        \\__kernel_data_end:
        \\__kernel_bss_start:
        \\__kernel_bss_end:
    );
}
