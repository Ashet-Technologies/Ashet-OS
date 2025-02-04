const std = @import("std");
const logger = std.log.scoped(.ashet_hc);
const ashet = @import("../../../../main.zig");

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = true, .bss = true },
    .memory_protection = null,
};

const hw = struct {
    //! list of fixed hardware components

};

pub fn get_tick_count() u64 {
    var cs = ashet.CriticalSection.enter();
    defer cs.leave();

    return systick.total_count_ms;
}

var interrupt_table: ashet.platform.profile.start.InterruptTable align(128) = ashet.platform.profile.start.initial_vector_table;

pub fn initialize() !void {
    logger.info("cpuid: {s}", .{
        ashet.platform.profile.registers.system_control_block.cpuid.read(),
    });

    // Remap interrupt table:
    ashet.platform.profile.registers.system_control_block.vtor.write(.{
        .table_offset = @truncate(@intFromPtr(&interrupt_table) >> 7),
    });

    logger.info("initialize SysTick...", .{});
    systick.init();
}

pub fn debugWrite(msg: []const u8) void {
    _ = msg;
    // const pl011: *volatile ashet.drivers.serial.PL011.Registers = @ptrFromInt(mmap.uart0.offset);
    // const old_cr = pl011.CR;
    // defer pl011.CR = old_cr;

    // pl011.CR |= (1 << 8) | (1 << 0);

    // for (msg) |c| {
    //     pl011.DR = c;
    // }
}

extern const __machine_linmem_start: u8 align(4);
extern const __machine_linmem_end: u8 align(4);

pub fn getLinearMemoryRegion() ashet.memory.Range {
    const linmem_start = @intFromPtr(&__machine_linmem_start);
    const linmem_end = @intFromPtr(&__machine_linmem_end);
    return .{ .base = linmem_start, .length = linmem_end - linmem_start };
}

const systick = struct {
    const regs = ashet.platform.profile.registers.sys_tick;

    var total_count_ms: u64 = 0;

    fn init() void {
        const calib = regs.calib.read();

        if (calib.ten_ms == 0) {
            @panic("Virtual SysTick requires known 10ms calibration, but none present!");
        }
        if (calib.skew != .exact) {
            logger.warn("SysTick has time skew!", .{});
        }

        regs.rvr.write(.{ .reload = @max(1, calib.ten_ms / 10) });

        interrupt_table.systick = increment_clock_irq;

        regs.csr.modify(.{
            .enabled = true,
            .interrupt = .enabled,
            .clock_source = .external_clock,
        });
    }

    fn increment_clock_irq() callconv(.C) void {
        total_count_ms +%= 1;
    }
};
