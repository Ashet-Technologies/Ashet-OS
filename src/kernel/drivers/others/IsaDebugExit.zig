//!
//! This driver implements means to exit a QEMU virtual machine
//! based on the `isa-debug-exit` device.
//!
const std = @import("std");

const ashet = @import("../../main.zig");

// QEMU default values:
const iobase = 1281;
const iosize = 2;

/// Exits the virtual machine.
pub fn exit(code: u8) void {
    ashet.ports.platforms.x86.out(switch (iosize) {
        1 => u8,
        2 => u16,
        4 => u32,
        else => @compileError("Invalid I/O size!"),
    }, code);
}
