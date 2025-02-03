const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const abi = ashet.abi;
const syscalls = ashet.userland;
const io = ashet.userland.io;

pub fn main() !void {
    _ = try ashet.process.debug.log_writer(.notice).write("Init system says hello!\r\n");

    // const apps_dir = try ashet.overlapped.performOne(abi.fs.OpenDrive, .{
    //     .fs = .system,
    //     .path_ptr = "apps",
    //     .path_len = 4,
    // });
    // defer apps_dir.dir.release();

    // const shm_handle = try syscalls.shm.create(4096);
    // defer shm_handle.release();

    // const shm = syscalls.shm.get_pointer(shm_handle)[0..syscalls.shm.get_length(shm_handle)];
    // @memset(shm, 0x00);
    // @memcpy(shm[0..22], "This is shared memory!");

    // const behaviour_proc = try ashet.overlapped.performOne(abi.process.Spawn, .{
    //     .dir = apps_dir.dir,
    //     .path_ptr = "testing/behaviour.ashex",
    //     .path_len = 23,
    //     .argv_ptr = &[_]abi.SpawnProcessArg{
    //         abi.SpawnProcessArg.string("--shared"),
    //         abi.SpawnProcessArg.resource(shm_handle.as_resource()),
    //         abi.SpawnProcessArg.string("hello, this is text"),
    //     },
    //     .argv_len = 3,
    // });
    // defer behaviour_proc.process.release();

    // std.log.info("spawned behaviour process: {}", .{behaviour_proc});

    // const desktop_proc = try ashet.overlapped.performOne(abi.process.Spawn, .{
    //     .dir = apps_dir.dir,
    //     .path_ptr = "desktop/classic.ashex",
    //     .path_len = 21,
    //     .argv_ptr = &[_]abi.SpawnProcessArg{},
    //     .argv_len = 0,
    // });
    // defer desktop_proc.process.release();

    // std.log.info("spawned desktop process: {}", .{desktop_proc});

    // TODO: await spawned process to exit, then print contents of shm!

    // for (0..10) |_| {
    //     const spare_shm_handle = try syscalls.shm.create(4096);

    //     std.log.info("shm: ptr=0x{X:0>8}, size={}", .{
    //         @intFromPtr(syscalls.shm.get_pointer(spare_shm_handle)),
    //         syscalls.shm.get_length(spare_shm_handle),
    //     });
    // }
}
