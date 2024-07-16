const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() !void {
    _ = try ashet.debug.writer().write("Init system says hello!\r\n");

    // while (true) {
    //     ashet.process.yield();
    // }

    for (0..10) |_| {
        const shm = ashet.abi.syscalls.@"ashet.shm.create"(4096) orelse return error.OutOfMemory;

        std.log.info("shm: ptr=0x{X:0>8}, size={}", .{
            @intFromPtr(ashet.abi.syscalls.@"ashet.shm.get_pointer"(shm)),
            ashet.abi.syscalls.@"ashet.shm.get_length"(shm),
        });
    }
}
