const std = @import("std");
const options = @import("options");

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const sys_argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, sys_argv);

    const argv = try std.mem.concat(allocator, []const u8, &.{
        &.{
            options.interpreter,
            options.script,
        },
        sys_argv[1..], // snip off the exe name
    });

    var child_process = std.process.Child.init(
        argv,
        allocator,
    );

    const term = try child_process.spawnAndWait();

    return switch (term) {
        .Exited => |code| code,
        else => @panic("bad child term!"),
    };
}
