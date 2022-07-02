const std = @import("std");
const ashet = @import("ashet");

comptime {
    _ = ashet;
}

pub fn main() void {
    const string = "#> echo \"This is a fake!\"\r\nThis is a fake!\r\n#> ";
    ashet.syscalls().console.print(string, string.len);
}
