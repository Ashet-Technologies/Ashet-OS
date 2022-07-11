const std = @import("std");
const ashet = @import("ashet");

comptime {
    _ = ashet;
}

pub fn main() void {
    ashet.syscalls().video.setResolution(256, 128);
    ashet.syscalls().video.setMode(.graphics);
    ashet.syscalls().video.setBorder(2);

    std.mem.copy(
        u8,
        ashet.syscalls().video.getVideoMemory()[0..32768],
        @embedFile("mediaplayer.raw"),
    );

    while (true) {
        ashet.syscalls().process.yield();
    }
}
