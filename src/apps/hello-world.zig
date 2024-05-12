const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

extern fn @"ashet-os.syscalls.demo1"() void;
extern fn @"ashet-os.syscalls.demo2"() void;

pub fn main() !void {
    @"ashet-os.syscalls.demo1"();
    @"ashet-os.syscalls.demo2"();
    _ = try ashet.debug.writer().write("hello, world!\r\n");
}
