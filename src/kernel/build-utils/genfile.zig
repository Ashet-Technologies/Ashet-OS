const std = @import("std");

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const argv = try init.minimal.args.toSlice(allocator);
    std.debug.assert(argv.len >= 1);

    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);

    for (argv[1..]) |data| {
        try writer.interface.print("{s}\n", .{data});
    }

    try writer.interface.flush();

    return 0;
}
