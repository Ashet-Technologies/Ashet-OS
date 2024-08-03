const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const abi = ashet.abi_v2;
const syscalls = ashet.userland.syscalls;
const io = ashet.userland.io;

pub fn main() !void {
    _ = try ashet.debug.writer().write("Init system says hello!\r\n");

    const apps_dir = try performOne(abi.io.fs.OpenDrive, .{
        .fs = .system,
        .path_ptr = "apps",
        .path_len = 4,
    });

    const desktop_proc = try performOne(abi.io.process.Spawn, .{
        .dir = apps_dir.dir,
        .path_ptr = "desktop/classic",
        .path_len = 15,
        .argv_ptr = &[_]abi.SpawnProcessArg{},
        .argv_len = 0,
    });

    std.log.info("spawned desktop process: {}", .{desktop_proc});

    for (0..10) |_| {
        const shm = ashet.abi.syscalls.@"ashet.shm.create"(4096) orelse return error.OutOfMemory;

        std.log.info("shm: ptr=0x{X:0>8}, size={}", .{
            @intFromPtr(ashet.abi.syscalls.@"ashet.shm.get_pointer"(shm)),
            ashet.abi.syscalls.@"ashet.shm.get_length"(shm),
        });
    }
}

pub fn singleShot(op: anytype) !void {
    const Type = @TypeOf(op);
    const ti = @typeInfo(Type);
    if (comptime (ti != .Pointer or ti.Pointer.size != .One))
        @compileError("singleShot expects a pointer to an IOP instance");
    const event: *abi.AsyncOp = &op.async_op;

    const result = syscalls.aops.schedule_and_await(event, .wait_all);
    std.debug.assert(result != null);
    std.debug.assert(result.? == event);

    try op.check_error();
}

pub fn performOne(comptime T: type, inputs: T.Inputs) (T.Error || error{Unexpected})!T.Outputs {
    var value = T.new(inputs);
    try singleShot(&value);
    return value.outputs;
}
