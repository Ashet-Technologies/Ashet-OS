// memory-region: system
//   0000000000000000-ffffffffffffffff (prio 0, i/o): system
//     0000000000000000-0000000003ffffff (prio 0, romd): virt.flash0
//     0000000004000000-0000000007ffffff (prio 0, romd): virt.flash1
//     0000000008000000-0000000008000fff (prio 0, i/o): gic_dist
//     0000000008010000-0000000008011fff (prio 0, i/o): gic_cpu
//     0000000008020000-0000000008020fff (prio 0, i/o): gicv2m
//     0000000009000000-0000000009000fff (prio 0, i/o): pl011
//     0000000009010000-0000000009010fff (prio 0, i/o): pl031
//     0000000009020000-0000000009020007 (prio 0, i/o): fwcfg.data
//     0000000009020008-0000000009020009 (prio 0, i/o): fwcfg.ctl
//     0000000009020010-0000000009020017 (prio 0, i/o): fwcfg.dma
//     0000000009030000-0000000009030fff (prio 0, i/o): pl061
//     000000000a000000-000000000a0001ff (prio 0, i/o): virtio-mmio
//     000000000a000200-000000000a0003ff (prio 0, i/o): virtio-mmio
//     000000000a000400-000000000a0005ff (prio 0, i/o): virtio-mmio
//     000000000a000600-000000000a0007ff (prio 0, i/o): virtio-mmio
//     000000000a000800-000000000a0009ff (prio 0, i/o): virtio-mmio
//     000000000a000a00-000000000a000bff (prio 0, i/o): virtio-mmio
//     000000000a000c00-000000000a000dff (prio 0, i/o): virtio-mmio
//     000000000a000e00-000000000a000fff (prio 0, i/o): virtio-mmio
//     000000000a001000-000000000a0011ff (prio 0, i/o): virtio-mmio
//     000000000a001200-000000000a0013ff (prio 0, i/o): virtio-mmio
//     000000000a001400-000000000a0015ff (prio 0, i/o): virtio-mmio
//     000000000a001600-000000000a0017ff (prio 0, i/o): virtio-mmio
//     000000000a001800-000000000a0019ff (prio 0, i/o): virtio-mmio
//     000000000a001a00-000000000a001bff (prio 0, i/o): virtio-mmio
//     000000000a001c00-000000000a001dff (prio 0, i/o): virtio-mmio
//     000000000a001e00-000000000a001fff (prio 0, i/o): virtio-mmio
//     000000000a002000-000000000a0021ff (prio 0, i/o): virtio-mmio
//     000000000a002200-000000000a0023ff (prio 0, i/o): virtio-mmio
//     000000000a002400-000000000a0025ff (prio 0, i/o): virtio-mmio
//     000000000a002600-000000000a0027ff (prio 0, i/o): virtio-mmio
//     000000000a002800-000000000a0029ff (prio 0, i/o): virtio-mmio
//     000000000a002a00-000000000a002bff (prio 0, i/o): virtio-mmio
//     000000000a002c00-000000000a002dff (prio 0, i/o): virtio-mmio
//     000000000a002e00-000000000a002fff (prio 0, i/o): virtio-mmio
//     000000000a003000-000000000a0031ff (prio 0, i/o): virtio-mmio
//     000000000a003200-000000000a0033ff (prio 0, i/o): virtio-mmio
//     000000000a003400-000000000a0035ff (prio 0, i/o): virtio-mmio
//     000000000a003600-000000000a0037ff (prio 0, i/o): virtio-mmio
//     000000000a003800-000000000a0039ff (prio 0, i/o): virtio-mmio
//     000000000a003a00-000000000a003bff (prio 0, i/o): virtio-mmio
//     000000000a003c00-000000000a003dff (prio 0, i/o): virtio-mmio
//     000000000a003e00-000000000a003fff (prio 0, i/o): virtio-mmio
//     000000000c000000-000000000dffffff (prio 0, i/o): platform bus
//     0000000010000000-000000003efeffff (prio 0, i/o): alias pcie-mmio @gpex_mmio_window 0000000010000000-000000003efeffff
//     000000003eff0000-000000003effffff (prio 0, i/o): gpex_ioport_window
//       000000003eff0000-000000003effffff (prio 0, i/o): gpex_ioport
//     0000000040000000-0000000047ffffff (prio 0, ram): mach-virt.ram
//     0000004010000000-000000401fffffff (prio 0, i/o): alias pcie-ecam @pcie-mmcfg-mmio 0000000000000000-000000000fffffff
//     0000008000000000-000000ffffffffff (prio 0, i/o): alias pcie-mmio-high @gpex_mmio_window 0000008000000000-000000ffffffffff

const std = @import("std");
const logger = std.log.scoped(.arm_virt);
const ashet = @import("../../../main.zig");

const virtio_config = ashet.drivers.VirtIoConfiguration{
    .base = 0x0A00_0000,
    .max_count = 32,
    .desc_size = 0x200,
};

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = true, .bss = true },
};

const hw = struct {
    //! list of fixed hardware components
    var uart: ashet.drivers.serial.PL011 = undefined;
    var cfi: ashet.drivers.block.CFI_NOR_Flash = undefined;
    var rtc: ashet.drivers.rtc.PL031 = undefined;
};

pub fn get_tick_count() u64 {
    return 0; // TODO: Implement precision timer
}

pub fn initialize() !void {
    logger.info("initialize PL011 uart...", .{});
    hw.uart = ashet.drivers.serial.PL011.init(0x0900_0000);

    logger.info("initialize PL031 rtc...", .{});
    hw.rtc = ashet.drivers.rtc.PL031.init(0x0901_0000);

    logger.info("initialize CFI flash...", .{});
    hw.cfi = try ashet.drivers.block.CFI_NOR_Flash.init(0x0400_0000, 0x0400_0000);

    logger.info("scan virtio devices...", .{});
    try ashet.drivers.scanVirtioDevices(ashet.memory.allocator, virtio_config);

    ashet.drivers.install(&hw.uart.driver);
    ashet.drivers.install(&hw.rtc.driver);
    ashet.drivers.install(&hw.cfi.driver);
}

pub fn debugWrite(msg: []const u8) void {
    const pl011: *volatile ashet.drivers.serial.PL011.Registers = @ptrFromInt(0x0900_0000);
    for (msg) |c| {
        pl011.DR = c;
    }
}

extern const __machine_linmem_start: u8 align(4);
extern const __machine_linmem_end: u8 align(4);

pub fn getLinearMemoryRegion() ashet.memory.Section {
    const linmem_start = @intFromPtr(&__machine_linmem_start);
    const linmem_end = @intFromPtr(&__machine_linmem_end);
    return ashet.memory.Section{ .offset = linmem_start, .length = linmem_end - linmem_start };
}
