const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);

    if (argv.len != 4)
        @panic("usage: checksize <src> <dst> <targetsize>");

    const input_name = argv[1];
    const output_name = argv[2];
    const targetsize = try std.fmt.parseInt(usize, argv[3], 10);

    const size = blk: {
        const input_file = try std.fs.cwd().openFile(input_name, .{});
        defer input_file.close();

        const input_stat = try input_file.stat();
        if (input_stat.size > targetsize) return error.FileTooBig;
        break :blk input_stat.size;
    };

    try std.fs.cwd().copyFile(input_name, std.fs.cwd(), output_name, .{});

    const output_file = try std.fs.cwd().openFile(output_name, .{ .mode = .read_write });
    defer output_file.close();

    try output_file.seekFromEnd(0);
    try output_file.writer().writeByteNTimes(0, @intCast(targetsize - size));
}
