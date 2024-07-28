// memory-region: system
//   0000000000000000-ffffffffffffffff (prio 0, i/o): system
//     0000000000001000-000000000000ffff (prio 0, rom): riscv_virt_board.mrom
//     0000000000100000-0000000000100fff (prio 0, i/o): riscv.sifive.test
//     0000000000101000-0000000000101023 (prio 0, i/o): goldfish_rtc
//     0000000002000000-0000000002003fff (prio 0, i/o): riscv.aclint.swi
//     0000000002004000-000000000200bfff (prio 0, i/o): riscv.aclint.mtimer
//     0000000003000000-000000000300ffff (prio 0, i/o): gpex_ioport_window
//       0000000003000000-000000000300ffff (prio 0, i/o): gpex_ioport
//     0000000004000000-0000000005ffffff (prio 0, i/o): platform bus
//     000000000c000000-000000000c5fffff (prio 0, i/o): riscv.sifive.plic
//     0000000010000000-0000000010000007 (prio 0, i/o): serial
//     0000000010001000-00000000100011ff (prio 0, i/o): virtio-mmio
//     0000000010002000-00000000100021ff (prio 0, i/o): virtio-mmio
//     0000000010003000-00000000100031ff (prio 0, i/o): virtio-mmio
//     0000000010004000-00000000100041ff (prio 0, i/o): virtio-mmio
//     0000000010005000-00000000100051ff (prio 0, i/o): virtio-mmio
//     0000000010006000-00000000100061ff (prio 0, i/o): virtio-mmio
//     0000000010007000-00000000100071ff (prio 0, i/o): virtio-mmio
//     0000000010008000-00000000100081ff (prio 0, i/o): virtio-mmio
//     0000000010100000-0000000010100007 (prio 0, i/o): fwcfg.data
//     0000000010100008-0000000010100009 (prio 0, i/o): fwcfg.ctl
//     0000000010100010-0000000010100017 (prio 0, i/o): fwcfg.dma
//     0000000020000000-0000000021ffffff (prio 0, romd): virt.flash0
//     0000000022000000-0000000023ffffff (prio 0, romd): virt.flash1
//     0000000030000000-000000003fffffff (prio 0, i/o): alias pcie-ecam @pcie-mmcfg-mmio 0000000000000000-000000000fffffff
//     0000000040000000-000000007fffffff (prio 0, i/o): alias pcie-mmio @gpex_mmio_window 0000000040000000-000000007fffffff
//     0000000080000000-0000000087ffffff (prio 0, ram): riscv_virt_board.ram
//     0000000300000000-00000003ffffffff (prio 0, i/o): alias pcie-mmio-high @gpex_mmio_window 0000000300000000-00000003ffffffff

const std = @import("std");
const ashet = @import("../../../main.zig");
const rv32 = ashet.ports.platforms.riscv;
const logger = std.log.scoped(.@"qemu-virt-rv32");

const VPBA_UART_BASE = 0x10000000;

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = true, .bss = true },
    .memory_protection = .{
        .initialize = rv32.vmm.initialize,
        .update = rv32.vmm.update,
        .activate = rv32.vmm.activate,
        .get_protection = rv32.vmm.get_protection,
        .get_info = rv32.vmm.query_address,
    },
};

const virtio_config = ashet.drivers.VirtIoConfiguration{
    .base = 0x10001000,
    .max_count = 8,
    .desc_size = 0x1000,
};

const hw = struct {
    //! list of fixed hardware components
    var rtc: ashet.drivers.rtc.Goldfish = undefined;
    var cfi: ashet.drivers.block.CFI_NOR_Flash = undefined;
};

pub fn get_tick_count() u64 {
    return 0; // TODO: Implement precision timer
}

pub fn initialize() !void {
    dump_machine_info();

    hw.rtc = ashet.drivers.rtc.Goldfish.init(0x0101000);
    hw.cfi = try ashet.drivers.block.CFI_NOR_Flash.init(0x2200_0000, 0x0200_0000);

    try ashet.drivers.scanVirtioDevices(ashet.memory.allocator, virtio_config);

    ashet.drivers.install(&hw.rtc.driver);
    ashet.drivers.install(&hw.cfi.driver);
}

pub fn debugWrite(msg: []const u8) void {
    for (msg) |c| {
        @as(*volatile u8, @ptrFromInt(VPBA_UART_BASE)).* = c;
    }
}

// pub const flash = ashet.memory.Section{ .offset = 0x2000_000, .length = 0x200_0000 };

extern const __machine_linmem_start: u8 align(4);
extern const __machine_linmem_end: u8 align(4);

pub fn getLinearMemoryRegion() ashet.memory.Range {
    const linmem_start = @intFromPtr(&__machine_linmem_start);
    const linmem_end = @intFromPtr(&__machine_linmem_end);
    return .{ .base = linmem_start, .length = linmem_end - linmem_start };
}

// /// Defines which serial ports are available to the system
// pub const Port = enum {
//     COM1,
// };

// pub fn isOnline(port: Port) bool {
//     // virtual ports are always online
//     _ = port;
//     return true;
// }

// pub fn write(port: Port, string: []const u8) void {
//     _ = port;
//     for (string) |char| {
//         @intToPtr(*volatile u8, @import("regs.zig").VPBA_UART_BASE).* = char;
//     }
// }

fn dump_machine_info() void {
    const vendor_id = rv32.ControlStatusRegister.read(.mvendorid);
    const arch_id = rv32.ControlStatusRegister.read(.marchid);
    const imp_id = rv32.ControlStatusRegister.read(.mimpid);
    const hart_id = rv32.ControlStatusRegister.read(.mhartid);
    const isa = rv32.ControlStatusRegister.read(.misa);

    const ISA = packed struct(u32) {
        extensions: u26,

        _padding: u4,

        machine_xlen: enum(u2) {
            undefined = 0b00,
            @"32 bit" = 0b01,
            @"64 bit" = 0b10,
            @"128 bit" = 0b11,
        },
    };

    const isa_decoded: ISA = @bitCast(isa);

    var extension_str: [26]u8 = undefined;
    var extension_count: usize = 0;

    for (0..26) |i| {
        if ((isa_decoded.extensions & (@as(u32, 1) << @truncate(i))) != 0) {
            extension_str[extension_count] = @truncate('A' + i);
            extension_count += 1;
        }
    }

    logger.info("machine info:", .{});
    logger.info("  vendor:     0x{X:0>8}", .{vendor_id});
    logger.info("  arch:       0x{X:0>8}", .{arch_id});
    logger.info("  imp:        0x{X:0>8}", .{imp_id});
    logger.info("  hart:       0x{X:0>8}", .{hart_id});
    logger.info("  isa:        0x{X:0>8}", .{isa});
    logger.info("    xlen:     {s}", .{@tagName(isa_decoded.machine_xlen)});
    logger.info("    ext:      {s}", .{extension_str[0..extension_count]});
}
