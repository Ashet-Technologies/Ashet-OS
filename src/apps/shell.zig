const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() void {
    ashet.console.write("#> echo \"This is a fake!\"\r\nThis is a fake!\r\n#> ");
}
