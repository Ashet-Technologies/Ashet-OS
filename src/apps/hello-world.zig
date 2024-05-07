const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

extern fn @"ashet-os.syscalls.demo"() void;

pub fn main() !void {
    @"ashet-os.syscalls.demo"();
    try ashet.debug.writer().print("hello, world!\r\n", .{});
}
