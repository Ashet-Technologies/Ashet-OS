const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);

    if (argv.len < 3 or argv.len > 4)
        @panic("usage: bin2c <symbol_name> <src> <dst> [<align>] < file.bin > file.c");

    const symbol_name = argv[1];
    const alignment = if (argv.len == 3)
        try std.fmt.parseInt(u64, argv[4], 0)
    else
        1;

    var input = try std.fs.cwd().openFile(argv[2], .{});
    defer input.close();

    var output = try std.fs.cwd().createFile(argv[3], .{});
    defer output.close();

    var buffered_in = std.io.bufferedReader(input.reader());
    var buffered_out = std.io.bufferedWriter(output.writer());

    const reader = buffered_in.reader();
    const writer = buffered_out.writer();

    const Printer = struct {
        const line_limit = 16;

        line_len: u8 = 0,
        written: u64 = 0,
        writer: @TypeOf(writer),

        fn write(p: *@This(), byte: u8) !void {
            defer p.written += 1;

            if (p.line_len > 0) {
                try p.writer.writeAll(", ");
            } else {
                try p.writer.writeAll("    ");
            }
            try p.writer.print("0x{X:0>2}", .{byte});
            p.line_len += 1;
            if (p.line_len >= line_limit) {
                try p.writer.writeAll(",\n");
                p.line_len = 0;
            }
        }

        fn finish(p: *@This()) !void {
            if (p.line_len > 0) {
                try p.writer.writeAll(",\n");
            }
        }
    };

    var printer = Printer{ .writer = writer };

    {
        try writer.print("unsigned char {s}[] = {{\n", .{symbol_name});

        while (true) {
            var block: [8192]u8 = undefined;
            const len = try reader.readAll(&block);
            if (len == 0)
                break;

            for (block[0..len]) |byte| {
                try printer.write(byte);
            }
        }

        var padding_overhead = printer.written % alignment;

        if (padding_overhead > 0) {
            while (padding_overhead < alignment) : (padding_overhead += 1) {
                try printer.write(0x00);
            }
        }

        try printer.finish();

        try writer.writeAll("};\n\n");
    }

    var stat = try input.stat();

    try writer.print("const unsigned int {s}_len = {d};\n\n", .{
        symbol_name,
        printer.written,
    });
    try writer.print("const int {s}_mtime = {d};\n", .{
        symbol_name,
        @divTrunc(stat.mtime, std.time.ns_per_s),
    });
    try writer.writeAll("\n");

    try buffered_out.flush();
}
