const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() !void {
    const len = 20;
    var buf: [len]u8 = undefined;
    ashet.abi.syscalls.@"ashet.random.get_random"(&buf, len, .strict);
    _ = try ashet.debug.writer().print("bytes: {x}\n", .{buf});
}
