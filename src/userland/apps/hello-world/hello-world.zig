const std = @import("std");
const ashet = @import("ashet");

pub const std_options = ashet.core.std_options;
pub const panic = ashet.core.panic;
comptime {
    _ = ashet.core;
}

pub fn main() !void {
    try ashet.process.debug.log_writer(.notice).writeAll("Hello, World!\r\n");
}
