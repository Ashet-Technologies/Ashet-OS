const std = @import("std");
const ashet = @import("root");

pub const registers = struct {
    pub const VPBA_UART_BASE = 0x10000000;
    pub const VPBA_VIRTIO_BASE = 0x10001000;
};

pub const serial = @import("serial.zig");

pub fn initialize() void {
    //
}

pub const memory = struct {
    pub const flash = ashet.memory.Section{ .offset = 0x2000_000, .length = 0x200_0000 };
    pub const ram = ashet.memory.Section{ .offset = 0x8000_000, .length = 0x100_0000 };
};
