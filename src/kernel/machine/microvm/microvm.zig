//! QEMU microvm platform
//!
//! https://www.qemu.org/docs/master/system/i386/microvm.html
//!
//! System memory map:
//!     0000000000000000-0000000001ffffff (prio 0, ram): alias ram-below-4g @microvm.ram 0000000000000000-0000000001ffffff
//!     00000000000e0000-00000000000fffff (prio 1, ram): alias isa-bios @pc.bios 0000000000000000-000000000001ffff
//!     00000000fea00000-00000000fea00003 (prio 0, i/o): acpi-ged
//!     00000000fea00200-00000000fea00202 (prio 0, i/o): acpi-ged-regs
//!     00000000feb00000-00000000feb001ff (prio 0, i/o): virtio-mmio
//!     00000000feb00200-00000000feb003ff (prio 0, i/o): virtio-mmio
//!     00000000feb00400-00000000feb005ff (prio 0, i/o): virtio-mmio
//!     00000000feb00600-00000000feb007ff (prio 0, i/o): virtio-mmio
//!     00000000feb00800-00000000feb009ff (prio 0, i/o): virtio-mmio
//!     00000000feb00a00-00000000feb00bff (prio 0, i/o): virtio-mmio
//!     00000000feb00c00-00000000feb00dff (prio 0, i/o): virtio-mmio
//!     00000000feb00e00-00000000feb00fff (prio 0, i/o): virtio-mmio
//!     00000000feb01000-00000000feb011ff (prio 0, i/o): virtio-mmio
//!     00000000feb01200-00000000feb013ff (prio 0, i/o): virtio-mmio
//!     00000000feb01400-00000000feb015ff (prio 0, i/o): virtio-mmio
//!     00000000feb01600-00000000feb017ff (prio 0, i/o): virtio-mmio
//!     00000000feb01800-00000000feb019ff (prio 0, i/o): virtio-mmio
//!     00000000feb01a00-00000000feb01bff (prio 0, i/o): virtio-mmio
//!     00000000feb01c00-00000000feb01dff (prio 0, i/o): virtio-mmio
//!     00000000feb01e00-00000000feb01fff (prio 0, i/o): virtio-mmio
//!     00000000feb02000-00000000feb021ff (prio 0, i/o): virtio-mmio
//!     00000000feb02200-00000000feb023ff (prio 0, i/o): virtio-mmio
//!     00000000feb02400-00000000feb025ff (prio 0, i/o): virtio-mmio
//!     00000000feb02600-00000000feb027ff (prio 0, i/o): virtio-mmio
//!     00000000feb02800-00000000feb029ff (prio 0, i/o): virtio-mmio
//!     00000000feb02a00-00000000feb02bff (prio 0, i/o): virtio-mmio
//!     00000000feb02c00-00000000feb02dff (prio 0, i/o): virtio-mmio
//!     00000000feb02e00-00000000feb02fff (prio 0, i/o): virtio-mmio
//!     00000000fec00000-00000000fec00fff (prio 0, i/o): ioapic
//!     00000000fec10000-00000000fec10fff (prio 0, i/o): ioapic
//!     00000000fee00000-00000000feefffff (prio 4096, i/o): apic-msi
//!     00000000fffe0000-00000000ffffffff (prio 0, ram): pc.bios

const std = @import("std");
const ashet = @import("root");

const VPBA_UART_BASE = 0x10000000;
const VPBA_VIRTIO_BASE = 0x10001000;

const hw = struct {
    //! list of fixed hardware components
    // var rtc: ashet.drivers.rtc.Goldfish = undefined;
    // var cfi: ashet.drivers.block.CFI_NOR_Flash = undefined;
};

pub fn initialize() !void {
    // hw.rtc = ashet.drivers.rtc.Goldfish.init(0x0101000);
    // hw.cfi = try ashet.drivers.block.CFI_NOR_Flash.init(0x2200_0000, 0x0200_0000);

    try ashet.drivers.scanVirtioDevices(ashet.memory.allocator, 0xfeb0_0000, 8);

    // ashet.drivers.install(&hw.rtc.driver);
    // ashet.drivers.install(&hw.cfi.driver);
}

pub fn debugWrite(msg: []const u8) void {
    for (msg) |c| {
        @intToPtr(*volatile u8, VPBA_UART_BASE).* = c;
    }
}

// pub const flash = ashet.memory.Section{ .offset = 0x2000_000, .length = 0x200_0000 };

extern const __machine_linmem_start: anyopaque align(4);
extern const __machine_linmem_end: anyopaque align(4);

pub fn getLinearMemoryRegion() ashet.memory.Section {
    // const linmem_start = @ptrToInt(&__machine_linmem_start);
    // const linmem_end = @ptrToInt(&__machine_linmem_end);
    // return ashet.memory.Section{ .offset = linmem_start, .length = linmem_end - linmem_start };
    return ashet.memory.Section{ .offset = 0, .length = 0 };
}
