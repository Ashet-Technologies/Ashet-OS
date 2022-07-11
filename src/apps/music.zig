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
        var evt: ashet.abi.InputEvent = undefined;
        switch (ashet.syscalls().input.getEvent(&evt)) {
            .none => {},
            .keyboard => {
                print("mouse => {}\r\n", .{evt.keyboard});
            },
            .mouse => {
                print("keyboard => {}\r\n", .{evt.mouse});
            },
        }

        ashet.syscalls().process.yield();
    }
}

fn print(comptime fmt: []const u8, args: anytype) void {
    std.fmt.format(std.io.Writer(void, E, writeString){ .context = {} }, fmt, args) catch unreachable;
}

const E = error{};
fn writeString(_: void, buf: []const u8) E!usize {
    for (buf) |char| {
        @intToPtr(*volatile u8, 0x1000_0000).* = char;
    }
    return buf.len;
}
