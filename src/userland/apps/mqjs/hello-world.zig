const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() !void {
    try ashet.process.debug.log_writer(.notice).writeAll("Hello, World!\r\n");
}
