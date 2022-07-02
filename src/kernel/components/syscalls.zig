const std = @import("std");
const hal = @import("hal");
const ashet = @import("../main.zig");

const ashet_syscall_interface: ashet.abi.SysCallInterface align(16) = .{
    .console = .{
        .print = @"console.print",
    },
};

pub fn initialize() void {
    //
}

pub fn getInterfacePointer() *align(16) const ashet.abi.SysCallInterface {
    return &ashet_syscall_interface;
}

fn @"console.print"(ptr: [*]const u8, len: usize) callconv(.C) void {
    ashet.console.write(ptr[0..len]);
}
