//!
//! Hosted Linux PC
//!

const std = @import("std");
const ashet = @import("../../../../main.zig");
const network = @import("network");
const args_parser = @import("args");
const logger = std.log.scoped(.@"hosted-windows");
const hosted = @import("../../../hosted/initialize.zig");

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = false, .bss = false },
    .memory_protection = null,
    .initialize = initialize,
    .early_initialize = null,
    .debug_write = hosted.debug_write,
    .get_linear_memory_region = hosted.get_linear_memory_region,
    .get_tick_count_ms = hosted.get_tick_count_ms,
};

fn initialize() !void {
    try hosted.initialize(video_drivers);
}

const video_drivers: std.StaticStringMap(hosted.VideoDriverCtor) = .initComptime(.{});

comptime {
    // Provide some global symbols.
    // We can fake the {flash,data,bss}_{start,end} symbols,
    // as we know that these won't overlap with linmem anyways:
    asm (
    // Freakin' Windows linking.
    // On Windows, symbols are prefixed with an additional "_"!
        \\
        \\.global ___kernel_stack_start
        \\.global ___kernel_stack_end
        \\___kernel_stack_start:
        \\.space 8 * 1024 * 1024        # 8 MB of stack
        \\___kernel_stack_end:
        \\
        \\.align 4096
        \\.global ___kernel_flash_start
        \\.global ___kernel_flash_end
        \\.global ___kernel_data_start
        \\.global ___kernel_data_end
        \\.global ___kernel_bss_start
        \\.global ___kernel_bss_end
        \\___kernel_flash_start:
        \\___kernel_flash_end:
        \\___kernel_data_start:
        \\___kernel_data_end:
        \\___kernel_bss_start:
        \\___kernel_bss_end:
    );
}
