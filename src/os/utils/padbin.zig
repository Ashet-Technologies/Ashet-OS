const std = @import("std");

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);

    const args = try std.process.argsAlloc(arena.allocator());
    if (args.len != 4)
        @panic("Invalid argv!");
    const src_path = args[1];
    const dst_path = args[2];
    const size_str = args[3];

    const target_size = try std.fmt.parseInt(u64, size_str, 10);

    const cwd = std.fs.cwd();

    try std.fs.Dir.copyFile(
        cwd,
        src_path,
        cwd,
        dst_path,
        .{},
    );

    var dst = try cwd.openFile(dst_path, .{ .mode = .read_write });
    defer dst.close();

    try dst.setEndPos(target_size);
}
