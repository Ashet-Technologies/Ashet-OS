//! PrimeCell UART (PL011)
//! https://developer.arm.com/documentation/ddi0183/g
const std = @import("std");
const ashet = @import("../../main.zig");
const Driver = ashet.drivers.Driver;

const PL011 = @This();

const WriteMode = ashet.drivers.SerialPort.WriteMode;

driver: Driver = .{
    .name = "PL011",
    .class = .{
        .serial = .{
            .writeFn = writeSome,
        },
    },
},
regs: *volatile Registers,

pub fn init(base: usize) PL011 {
    return PL011{
        .regs = @ptrFromInt(base),
    };
}

fn pl011(dri: *Driver) *PL011 {
    return @fieldParentPtr(PL011, "driver", dri);
}

fn writeSome(dri: *Driver, msg: []const u8, mode: WriteMode) usize {
    _ = dri;
    _ = mode;
    return msg.len;
}

pub const Registers = extern struct {
    //!
    //! https://developer.arm.com/documentation/ddi0183/g/programmers-model/summary-of-registers
    //!

    DR: u32, // 0x000
    RSR_UARTECR: u32, // 0x004
    _reserved0: [3]u32, // 0x008 … 0x014
    FR: u32, // 0x018
    _reserved1: u32, // 0x01C
    ILPR: u32, // 0x020
    IBRD: u32, // 0x024
    FBRD: u32, // 0x028
    LCR_H: u32, // 0x02C
    CR: u32, // 0x030
    IFLS: u32, // 0x034
    IMSC: u32, // 0x038
    RIS: u32, // 0x03C
    MIS: u32, // 0x040
    ICR: u32, // 0x044
    DMACR: u32, // 0x048

    _reserved2: [998]u32, // 0x04C…0xFDC

    PeriphID0: u32, // 0xFE0
    PeriphID1: u32, // 0xFE4
    PeriphID2: u32, // 0xFE8
    PeriphID3: u32, // 0xFEC
    PCellID0: u32, // 0xFF0
    PCellID1: u32, // 0xFF4
    PCellID2: u32, // 0xFF8
    PCellID3: u32, // 0xFFC

    comptime {
        if (@sizeOf(@This()) != 0x1000) {
            @compileError(std.fmt.comptimePrint("PL011 registers must be exactly 0x1000 bytes large, but is 0x{X}.", .{@sizeOf(@This())}));
        }
    }

    comptime {
        if (@alignOf(@This()) != 4) {
            @compileError("PL011 registers must be aligned to 4.");
        }
    }
};
