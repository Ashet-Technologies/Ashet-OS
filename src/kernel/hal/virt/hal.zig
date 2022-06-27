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
