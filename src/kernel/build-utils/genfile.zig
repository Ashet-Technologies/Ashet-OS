const std = @import("std");

pub fn main() !u8 {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);
    std.debug.assert(argv.len >= 1);

    var stdout = std.io.getStdOut().writer();

    for (argv[1..]) |data| {
        try stdout.print("{s}\n", .{data});
    }

    return 0;
}
