const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);

    const args = try init.minimal.args.toSlice(arena.allocator());
    if (args.len != 4)
        @panic("Invalid argv!");
    const src_path = args[1];
    const dst_path = args[2];
    const size_str = args[3];

    const target_size = try std.fmt.parseInt(u64, size_str, 10);

    const cwd = std.Io.Dir.cwd();

    try std.Io.Dir.copyFile(
        cwd,
        src_path,
        cwd,
        dst_path,
        io,
        .{},
    );

    var dst = try cwd.openFile(io, dst_path, .{ .mode = .read_write });
    defer dst.close(io);

    try dst.setLength(io, target_size);
}
