const std = @import("std");
const hal = @import("hal.zig");

/// Defines which serial ports are available to the system
pub const Port = enum {
    COM1,
};

pub fn isOnline(port: Port) bool {
    // virtual ports are always online
    _ = port;
    return true;
}

pub fn write(port: Port, string: []const u8) void {
    _ = port;
    for (string) |char| {
        @intToPtr(*volatile u8, @import("regs.zig").VPBA_UART_BASE).* = char;
    }
}
