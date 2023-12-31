//! Implementation of the 8259 PIC interface.

const std = @import("std");
const x86 = @import("../x86.zig");
const logger = std.log.scoped(.idt);

const PIC = @This();

pub const primary = PIC{ .control = 0x20, .mask = 0x21 };
pub const secondary = PIC{ .control = 0xA0, .mask = 0xA1 };

pub const cascade_irq = 2;

control: u16,
mask: u16,

pub fn initialize(pic: PIC, vector_offset: u8) void {
    std.debug.assert(std.mem.isAligned(vector_offset, 8));

    const sequence = [4]u8{
        @as(u8, @bitCast(ICW1{
            .icw4 = true,
            .mode = .cascade,
            .trigger = .edge,
            .address_interval = .@"8",
        })),

        @as(ICW2, vector_offset),

        @as(u8, @bitCast(if (pic.control == primary.control)
            ICW3{ .primary = .{ .mask = 1 << cascade_irq } }
        else
            ICW3{ .secondary = .{ .id = cascade_irq } })),

        @as(u8, @bitCast(ICW4{
            .mode = .@"8086",
            .auto_eoi = false,
            .buffer_mode = .unbuffered,
            .fully_nested = false,
        })),
    };

    x86.out(u8, pic.control, sequence[0]);
    x86.waitIO();

    x86.out(u8, pic.mask, sequence[1]);
    x86.waitIO();

    x86.out(u8, pic.mask, sequence[2]);
    x86.waitIO();

    x86.out(u8, pic.mask, sequence[3]);
    x86.waitIO();
}

pub fn notifyEndOfInterrupt(pic: PIC) void {
    x86.out(u8, pic.control, 0x20); // Send EOI
}

pub fn disable(pic: PIC, irq: u3) void {
    const mask = @as(u8, 1) << irq;

    var val = x86.in(u8, pic.mask);
    val |= mask;
    x86.out(u8, pic.mask, val);
}

pub fn enable(pic: PIC, irq: u3) void {
    const mask = @as(u8, 1) << irq;

    var val = x86.in(u8, pic.mask);
    val &= ~mask;
    x86.out(u8, pic.mask, val);
}

pub fn enableAll(pic: PIC) void {
    x86.out(u8, pic.mask, 0x00);
}

pub fn disableAll(pic: PIC) void {
    x86.out(u8, pic.mask, 0xFF);
}

const ICW1 = packed struct(u8) {
    icw4: bool, // requires icw4
    mode: enum(u1) { cascade = 0, single = 1 },
    address_interval: enum(u1) { @"8", @"4" },
    trigger: enum(u1) { edge = 0, level = 1 },
    marker: u1 = 0x1,
    a_567: u3 = 0, // only required in MCS-80 mode
};

const ICW2 = u8; // D7…D3 are the interrupt number, D2…D0 must be 0

const ICW3 = extern union {
    primary: packed struct(u8) {
        mask: u8,
    },
    secondary: packed struct(u8) {
        id: u3,
        padding: u5 = 0,
    },
};

const ICW4 = packed struct(u8) {
    mode: enum(u1) { @"mcs-80" = 0, @"8086" = 1 },
    auto_eoi: bool,
    buffer_mode: enum(u2) {
        unbuffered = 0b00,
        primary = 0b11,
        secondary = 0b10,
    },
    fully_nested: bool,
    padding: u3 = 0,
};
