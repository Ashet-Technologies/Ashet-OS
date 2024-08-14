const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const abi = ashet.abi;
const syscalls = ashet.userland;
const io = ashet.userland.io;

pub fn main() !void {
    _ = try ashet.process.debug.log_writer(.notice).write("Init system says hello!\r\n");

    const apps_dir = try ashet.io.performOne(abi.fs.OpenDrive, .{
        .fs = .system,
        .path_ptr = "apps",
        .path_len = 4,
    });

    const desktop_proc = try ashet.io.performOne(abi.process.Spawn, .{
        .dir = apps_dir.dir,
        .path_ptr = "desktop/classic",
        .path_len = 15,
        .argv_ptr = &[_]abi.SpawnProcessArg{},
        .argv_len = 0,
    });

    std.log.info("spawned desktop process: {}", .{desktop_proc});

    for (0..10) |_| {
        const shm = try syscalls.shm.create(4096);

        std.log.info("shm: ptr=0x{X:0>8}, size={}", .{
            @intFromPtr(syscalls.shm.get_pointer(shm)),
            syscalls.shm.get_length(shm),
        });
    }
}
