const std = @import("std");
const hal = @import("hal");
const ashet = @import("../main.zig");

const abi = ashet.abi;

const ashet_syscall_interface: abi.SysCallInterface align(16) = .{
    .console = .{
        .print = @"console.print",
    },
    .video = .{
        .setMode = @"video.setMode",
        .setBorder = @"video.setBorder",
        .getVideoMemory = @"video.getVideoMemory",
        .getPaletteMemory = @"video.getPaletteMemory",
    },
    .process = .{
        .exit = @"process.exit",
    },
};

pub fn initialize() void {
    //
}

pub fn getInterfacePointer() *align(16) const abi.SysCallInterface {
    return &ashet_syscall_interface;
}

fn @"console.print"(ptr: [*]const u8, len: usize) callconv(.C) void {
    ashet.console.write(ptr[0..len]);
}

fn @"video.setMode"(mode: abi.VideoMode) callconv(.C) void {
    ashet.video.setMode(mode);
}
fn @"video.setBorder"(color: abi.ColorIndex) callconv(.C) void {
    ashet.video.setBorder(color);
}
fn @"video.getVideoMemory"() callconv(.C) [*]abi.ColorIndex {
    return ashet.video.memory.ptr;
}
fn @"video.getPaletteMemory"() callconv(.C) *[abi.palette_size]u16 {
    return ashet.video.palette;
}

fn @"process.exit"(exit_code: u32) callconv(.C) noreturn {
    ashet.scheduler.exit(exit_code);
}
