const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

extern fn @"ashet-os.syscalls.demo1"() void;
extern fn @"ashet-os.syscalls.demo2"() void;

pub fn main() !void {
    _ = try ashet.debug.writer().write("Hello, World!\r\n");
}
