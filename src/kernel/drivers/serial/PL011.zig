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
    return @fieldParentPtr("driver", dri);
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
    RSR_ECR: u32, // 0x004
    _reserved0: [4]u32, // 0x008 … 0x014
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

    _reserved2: [997]u32, // 0x04C…0xFDC

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

    comptime {
        for (register_info) |reg| {
            const offset, const name = reg;
            if (@offsetOf(@This(), name) != offset) {
                @compileError(std.fmt.comptimePrint("Expected '{s}' to have offset 0x{X:0>3}, but found 0x{X:0>3}.", .{
                    name, offset, @offsetOf(@This(), name),
                }));
            }
        }
    }
};

const register_info = [_]struct { u32, []const u8 }{
    .{ 0x000, "DR" },
    .{ 0x004, "RSR_ECR" },
    .{ 0x018, "FR" },
    .{ 0x020, "ILPR" },
    .{ 0x024, "IBRD" },
    .{ 0x028, "FBRD" },
    .{ 0x02C, "LCR_H" },
    .{ 0x030, "CR" },
    .{ 0x034, "IFLS" },
    .{ 0x038, "IMSC" },
    .{ 0x03C, "RIS" },
    .{ 0x040, "MIS" },
    .{ 0x044, "ICR" },
    .{ 0x048, "DMACR" },
    .{ 0xFE0, "PeriphID0" },
    .{ 0xFE4, "PeriphID1" },
    .{ 0xFE8, "PeriphID2" },
    .{ 0xFEC, "PeriphID3" },
    .{ 0xFF0, "PCellID0" },
    .{ 0xFF4, "PCellID1" },
    .{ 0xFF8, "PCellID2" },
    .{ 0xFFC, "PCellID3" },
};
