const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const syscalls = ashet.userland;

pub fn main() !void {
    std.log.info("START TESTING/BEHAVIOUR", .{});
    defer std.log.info("STOP TESTING/BEHAVIOUR", .{});

    var argv_buffer: [16]ashet.abi.SpawnProcessArg = undefined;
    const argv_len = try ashet.userland.process.get_arguments(null, &argv_buffer);
    const argv = argv_buffer[0..argv_len];

    std.log.info("arg count: {}", .{argv_len});
    for (argv, 0..) |arg, index| {
        switch (arg.type) {
            .string => std.log.info("  arg {}: \"{}\"", .{ index, std.zig.fmtEscapes(arg.value.text.slice()) }),
            .resource => std.log.info("  arg {}: {T}", .{ index, arg.value.resource }),
        }
    }

    std.log.info("arg count: {}", .{argv_len});
    for (argv) |arg| {
        if (arg.type != .resource)
            continue;

        const shm_handle = try arg.value.resource.cast(.shared_memory);

        const shm = (try syscalls.shm.get_pointer(shm_handle))[0..try syscalls.shm.get_length(shm_handle)];

        std.log.info("received \"{}\" via shm", .{
            std.zig.fmtEscapes(std.mem.sliceTo(shm, 0)),
        });
    }
}
