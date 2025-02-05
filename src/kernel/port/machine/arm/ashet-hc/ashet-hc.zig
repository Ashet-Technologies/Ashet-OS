const std = @import("std");
const logger = std.log.scoped(.ashet_hc);
const ashet = @import("../../../../main.zig");
const rp2350 = @import("rp2350");
const rp2350_regs = rp2350.devices.RP2350.peripherals;

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = true, .bss = true },
    .memory_protection = null,
    .early_initialize = early_initialize,
    .get_tick_count_ms = get_tick_count_ms,
    .initialize = initialize,
    .debug_write = debug_write,
    .get_linear_memory_region = get_linear_memory_region,
};

const hw = struct {
    //! list of fixed hardware components

};

fn get_tick_count_ms() u64 {
    var cs = ashet.CriticalSection.enter();
    defer cs.leave();

    return systick.total_count_ms;
}

var interrupt_table: ashet.platform.profile.start.InterruptTable align(128) = ashet.platform.profile.start.initial_vector_table;

fn early_initialize() void {
    // TODO: The following things are to be done here:
    // - Disable watchdogs
    // - Reset all unused peripherials
    // - Setup clocks and PLL
    // - Configure external RAM
    // - Initialize UART0 for debugging
}

fn initialize() !void {
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

fn debug_write(msg: []const u8) void {
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

fn get_linear_memory_region() ashet.memory.Range {
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

export const image_def align(64) linksection(".text.image_def") = [_]u32{
    // For explanation, see RP2350 Datasheet, Chapter "5.9.5. Minimum Viable Image Metadata":
    PICOBIN_BLOCK_MARKER_START,
    0x10210142, // IMAGE_TYPE = EXE + Secure Arm + RP2350
    0x000001ff, // End Marker Item, Total Size 1
    0x00000000, // Pointer to the next block (self loop)
    PICOBIN_BLOCK_MARKER_END,
};

const PICOBIN_BLOCK_MARKER_START = 0xffffded3;
const PICOBIN_BLOCK_MARKER_END = 0xab123579;
