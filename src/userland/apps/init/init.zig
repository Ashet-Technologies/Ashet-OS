const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() !void {
    @as(*u8, @ptrFromInt(0x80040000)).* = 0;
}
