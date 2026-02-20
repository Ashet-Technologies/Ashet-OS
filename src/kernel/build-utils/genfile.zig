const std = @import("std");

pub fn main() !u8 {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);
    std.debug.assert(argv.len >= 1);

    var buffer: [4096]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buffer);

    for (argv[1..]) |data| {
        try writer.interface.print("{s}\n", .{data});
    }

    try writer.interface.flush();

    return 0;
}
