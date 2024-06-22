const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() !void {
    _ = try ashet.debug.writer().write("Hello, World!\r\n");
}
