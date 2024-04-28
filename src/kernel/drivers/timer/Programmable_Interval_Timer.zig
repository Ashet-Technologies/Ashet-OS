//!
//! PROGRAMMABLE INTERVAL TIMER
//! https://www.scs.stanford.edu/09wi-cs140/pintos/specs/8254.pdf
//!

const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.pit);
const x86 = @import("platform.x86");

const PIT = @This();

pub const timer_frequency = 1_193_182; // Hz

pub const Register = enum(u16) {
    counter0 = 0x40, // 	Counter-Register für Channel 0 setzen/lesen
    counter1 = 0x41, // 	Counter-Register für Channel 1 setzen/lesen
    counter2 = 0x42, // 	Counter-Register für Channel 2 setzen/lesen
    control = 0x43, // 	Initalisierung (siehe unten)

};

fn write_reg(reg: Register, value: u8) void {
    x86.out(u8, @intFromEnum(reg), value);
}

fn read_reg(reg: Register) u8 {
    return x86.in(u8, @intFromEnum(reg));
}

pub fn init() PIT {
    write_reg(.control, @bitCast(ControlWord{
        .format = .binary,
        .mode = .mode2,
        .access = .lsb_then_msb,
        .channel = .chan0,
    }));

    const requested_frequency = 1000; // 100 kHz

    const counter_limit: u16 = timer_frequency / requested_frequency;

    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, counter_limit, .Little);
    write_reg(.counter0, bytes[0]);
    write_reg(.counter0, bytes[1]);

    return PIT{};
}

const ControlWord = packed struct(u8) {
    format: enum(u1) { binary = 0, bcd = 1 },
    mode: TimerMode,
    access: enum(u2) { internal = 0b00, lsb = 0b01, msb = 0b10, lsb_then_msb = 0b11 },
    channel: Channel,
};

const Channel = enum(u2) {
    chan0 = 0b00,
    chan1 = 0b01,
    chan2 = 0b10,
    read_back = 0b11,
};

const TimerMode = enum(u3) {
    /// Interrupt on terminal count
    mode0 = 0b000,
    /// Hardware Retriggerable One-Shot
    mode1 = 0b001,
    /// Rate Generator
    mode2 = 0b010, // 0bX10, but X should be 0
    /// Square Wave Generator
    mode3 = 0b011, // 0bX11, but X should be 0
    /// Software Triggered Strobe
    mode4 = 0b100,
    /// Hardware Triggered Strobe
    mode5 = 0b101,
};
