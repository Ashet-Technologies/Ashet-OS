const std = @import("std");
const ashet = @import("ashet");

pub const std_options = ashet.core.std_options;
comptime {
    _ = ashet.core;
}

const abi = ashet.abi;
const io = ashet.userland.io;

pub fn main() !void {
    _ = try ashet.process.debug.log_writer(.notice).write("Init system says hello!\r\n");

    var apps_dir = try ashet.fs.Directory.openDrive(.system, "apps");
    defer apps_dir.close();

    const shm_handle = try abi.shm.create(4096);
    defer shm_handle.release();

    const shm = (try abi.shm.get_pointer(shm_handle))[0..try abi.shm.get_length(shm_handle)];
    @memset(shm, 0x00);
    @memcpy(shm[0..22], "This is shared memory!");

    const behaviour_proc = try ashet.process.spawn(
        apps_dir,
        "testing/behaviour.ashex",
        &[_]abi.SpawnProcessArg{
            .string("--shared"),
            .resource(shm_handle.as_resource()),
            .string("hello, this is text"),
        },
    );
    defer behaviour_proc.release();

    std.log.info("spawned behaviour process: {}", .{behaviour_proc});

    const widgets_proc = try ashet.process.spawn(
        apps_dir,
        "widgets.ashex",
        &.{},
    );
    defer widgets_proc.release();

    std.log.info("spawned widgets service: {}", .{widgets_proc});

    const desktop_proc = try ashet.process.spawn(
        apps_dir,
        "desktop/classic.ashex",
        &.{},
    );
    defer desktop_proc.release();

    std.log.info("spawned desktop process: {}", .{desktop_proc});

    // TODO: await spawned process to exit, then print contents of shm!

    // for (0..10) |_| {
    //     const spare_shm_handle = try syscalls.shm.create(4096);

    //     std.log.info("shm: ptr=0x{X:0>8}, size={}", .{
    //         @intFromPtr(syscalls.shm.get_pointer(spare_shm_handle)),
    //         syscalls.shm.get_length(spare_shm_handle),
    //     });
    // }
}
