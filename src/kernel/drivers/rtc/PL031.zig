//! ARM PrimeCell Real Time Clock (PL031)
//! https://developer.arm.com/documentation/ddi0224/b
const std = @import("std");
const ashet = @import("../../main.zig");
const Driver = ashet.drivers.Driver;

const PL031 = @This();

driver: Driver = .{
    .name = "PL031",
    .class = .{
        .rtc = .{
            .nanoTimestampFn = nanoTimestamp,
        },
    },
},
regs: *volatile Registers,

pub fn init(base: usize) PL031 {
    return PL031{
        .regs = @ptrFromInt(base),
    };
}

fn pl031(dri: *Driver) *PL031 {
    return @fieldParentPtr(PL031, "driver", dri);
}

fn nanoTimestamp(dri: *Driver) i128 {
    const dr = pl031(dri).regs.DR;
    return @as(i128, std.time.ns_per_s) * dr;
}

pub const Registers = extern struct {
    //!
    //! https://developer.arm.com/documentation/ddi0224/b/Programmer-s-Model/Summary-of-PrimeCell-RTC-registers
    //!

    DR: u32, // 0x000
    MR: u32, // 0x004
    LR: u32, // 0x008
    CR: u32, // 0x00C
    IMSC: u32, // 0x010
    RIS: u32, // 0x014
    MIS: u32, // 0x018
    ICR: u32, // 0x01C

    _reserved2: [1008]u32, // 0x020…0xFDC

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
            @compileError("PL031 registers must be exactly 0x1000 bytes large.");
        }
    }

    comptime {
        if (@alignOf(@This()) != 4) {
            @compileError("PL031 registers must be aligned to 4.");
        }
    }
};
