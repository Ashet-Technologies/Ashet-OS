const std = @import("std");
const logger = std.log.scoped(.ashet_vhc);
const ashet = @import("../../../../main.zig");
const mmap = @import("mmap.zig");

const virtio_config = ashet.drivers.VirtIoConfiguration{
    .base = mmap.virtio0.offset,
    .max_count = 8,
    .desc_size = mmap.virtio1.offset - mmap.virtio0.offset,
};

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = true, .bss = true },
    .memory_protection = null,
};

const hw = struct {
    //! list of fixed hardware components
    var uart0: ashet.drivers.serial.PL011 = undefined;
    var uart1: ashet.drivers.serial.PL011 = undefined;
    var rtc: ashet.drivers.rtc.Goldfish = undefined;
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

    logger.info("initialize PL011 uart...", .{});
    hw.uart0 = ashet.drivers.serial.PL011.init(mmap.uart0.offset);
    hw.uart1 = ashet.drivers.serial.PL011.init(mmap.uart1.offset);

    logger.info("initialize Goldfish rtc...", .{});
    hw.rtc = ashet.drivers.rtc.Goldfish.init(mmap.goldfish.offset);

    // logger.info("initialize CFI flash...", .{});
    // hw.cfi = try ashet.drivers.block.CFI_NOR_Flash.init(0x0400_0000, 0x0400_0000);

    logger.info("scan virtio devices...", .{});
    try ashet.drivers.scanVirtioDevices(ashet.memory.allocator, virtio_config);

    // ashet.drivers.install(&hw.uart0.driver);
    // ashet.drivers.install(&hw.uart1.driver);
    ashet.drivers.install(&hw.rtc.driver);
    // ashet.drivers.install(&hw.cfi.driver);
}

pub fn debugWrite(msg: []const u8) void {
    const pl011: *volatile ashet.drivers.serial.PL011.Registers = @ptrFromInt(mmap.uart0.offset);
    const old_cr = pl011.CR;
    defer pl011.CR = old_cr;

    pl011.CR |= (1 << 8) | (1 << 0);

    for (msg) |c| {
        pl011.DR = c;
    }
}

pub fn binaryDebugWrite(msg: []const u8) void {
    const pl011: *volatile ashet.drivers.serial.PL011.Registers = @ptrFromInt(mmap.uart1.offset);
    const old_cr = pl011.CR;
    defer pl011.CR = old_cr;

    pl011.CR |= (1 << 8) | (1 << 0);

    for (msg) |c| {
        pl011.DR = c;
    }
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
