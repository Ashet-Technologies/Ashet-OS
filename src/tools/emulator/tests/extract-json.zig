const std = @import("std");

pub fn main() !void {
    var in_buffer: [4096]u8 = undefined;
    var out_buffer: [4096]u8 = undefined;

    var stdin_reader = std.fs.File.stdin().reader(&in_buffer);
    var stdout_writer = std.fs.File.stdout().writer(&out_buffer);

    const reader = &stdin_reader.interface;
    const writer = &stdout_writer.interface;

    while (true) {
        var line_buffer: [1024]u8 = undefined;
        var line_writer: std.Io.Writer = .fixed(&line_buffer);

        const count = try reader.streamDelimiterEnding(&line_writer, '\n');
        if (count == 0) {
            std.log.err("eof", .{});
            break;
        }
        std.debug.assert(try reader.takeByte() == '\n');

        const line = line_writer.buffered();

        if (!std.mem.startsWith(u8, line, "//"))
            break;

        try writer.writeAll(line[2..]);
        try writer.writeAll("\n");
    }

    try writer.flush();
}
