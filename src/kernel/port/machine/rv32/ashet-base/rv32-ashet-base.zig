const std = @import("std");
const ashet = @import("../../../../main.zig");
const rv32 = ashet.ports.platforms.riscv;
const logger = std.log.scoped(.@"qemu-ashet-base");

pub const peripherals = @import("peripherals.zig");

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = true, .bss = true },
    .memory_protection = null,
    .initialize = initialize,
    .early_initialize = null,
    .debug_write = debug_write,
    .get_linear_memory_region = get_linear_memory_region,
    .get_tick_count_ms = get_tick_count_ms,
    .halt = null,
};

const hw = struct {
    //! list of fixed hardware components

    var rtc: ashet.drivers.rtc.Ashet_RTC = undefined;

    var block0: ashet.drivers.block.Ashet_Block_Dev = undefined;
    var block1: ashet.drivers.block.Ashet_Block_Dev = undefined;
};

fn get_tick_count_ms() u64 { // return value in ms
    return peripherals.timer.read_mtime_us() / 1000;
}

fn initialize() !void {
    // TODO: Setup machine

    hw.rtc = .init(peripherals.timer);

    hw.block0 = .init(peripherals.block_device_0, "BD0");
    hw.block1 = .init(peripherals.block_device_1, "BD1");

    // Finally install all drivers:
    ashet.drivers.install(&hw.rtc.driver);
    ashet.drivers.install(&hw.block0.driver);
    ashet.drivers.install(&hw.block1.driver);
}

fn debug_write(msg: []const u8) void {
    for (msg) |c| {
        peripherals.debug_output.tx = c;
    }
}

extern const __kernel_ram_start: u8 align(4); // pointer to the first byte of RAM
extern const __machine_linmem_start: u8 align(4); // pointer to the first byte of RAM after all kernel data

fn get_linear_memory_region() ashet.memory.Range {
    const ram_start = @intFromPtr(&__kernel_ram_start);

    const linmem_start = @intFromPtr(&__machine_linmem_start);
    const linmem_end = ram_start + peripherals.system_info.ram_size;

    return .{ .base = linmem_start, .length = linmem_end - linmem_start };
}
