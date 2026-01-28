const std = @import("std");
const ashet = @import("ashet");

pub const std_options = ashet.core.std_options;
pub const panic = ashet.core.panic;
comptime {
    _ = ashet.core;
}

const abi = ashet.abi;

pub fn main() !void {
    std.log.info("START TESTING/BEHAVIOUR", .{});
    defer std.log.info("STOP TESTING/BEHAVIOUR", .{});

    var argv_buffer: [16]ashet.abi.SpawnProcessArg = undefined;
    const argv_len = try abi.process.get_arguments(null, &argv_buffer);
    const argv = argv_buffer[0..argv_len];

    std.log.info("arg count: {}", .{argv_len});
    for (argv, 0..) |arg, index| {
        switch (arg.type) {
            .string => std.log.info("  arg {}: \"{f}\"", .{ index, std.zig.fmtString(arg.value.text.slice()) }),
            .resource => std.log.info("  arg {}: {f}", .{ index, std.fmt.alt(arg.value.resource, .formatType) }),
        }
    }

    std.log.info("arg count: {}", .{argv_len});
    for (argv) |arg| {
        if (arg.type != .resource)
            continue;

        const shm_handle = try arg.value.resource.cast(.shared_memory);

        const shm = (try abi.shm.get_pointer(shm_handle))[0..try abi.shm.get_length(shm_handle)];

        std.log.info("received \"{f}\" via shm", .{
            std.zig.fmtString(std.mem.sliceTo(shm, 0)),
        });
    }
}
