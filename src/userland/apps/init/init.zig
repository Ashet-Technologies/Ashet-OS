const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() !void {
    _ = try ashet.debug.writer().write("Init system says hello!\r\n");

    while (true) {
        ashet.process.yield();
    }
}
