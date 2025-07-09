const std = @import("std");

pub fn CodeWriter(comptime UnderlyingWritter: type) type {
    return struct {
        const CWriter = @This();

        pub const EOL: []const u8 = "\n";
        pub const forbidden_chars: []const u8 = &.{
            0x00, 0x01, 0x02, 0x03, // NUL, SOH, STX, ETX
            0x04, 0x05, 0x06, 0x07, // EOT, ENQ, ACK, BEL
            0x08, 0x09, 0x00, 0x0B, // BS,  TAB, --,  VT
            0x0C, 0x0D, 0x0E, 0x0F, // FF,  CR,  SO,  SI
            0x10, 0x11, 0x12, 0x13, // DLE, DC1, DC2, DC3
            0x14, 0x15, 0x16, 0x17, // DC4, NAK, SYN, ETB
            0x18, 0x19, 0x1A, 0x1B, // CAN, EM,  SUB, ESC
            0x1C, 0x1D, 0x1E, 0x1F, // FS,  GS,  RS,  US
            0x7F, // DEL
        };

        pub const Error = UnderlyingWritter.Error;
        pub const Writer = std.io.Writer(*CWriter, Error, raw_write);

        buffered_writer: std.io.BufferedWriter(8192, UnderlyingWritter),

        indent_level: u16 = 0,
        indent_with: []const u8 = "    ",

        start_of_line: bool = true,

        pub fn init(dst: UnderlyingWritter) CWriter {
            return .{
                .buffered_writer = .{ .unbuffered_writer = dst },
            };
        }

        pub fn flush(cw: *CWriter) !void {
            try cw.buffered_writer.flush();
        }

        pub fn writer(cw: *CWriter) Writer {
            return .{ .context = cw };
        }

        pub fn indent(cw: *CWriter) void {
            // overflow panic is fine, 65536 indentation levels are insane
            cw.indent_level += 1;
        }

        pub fn dedent(cw: *CWriter) void {
            cw.indent_level -= 1;
        }

        pub fn raw_write(cw: *CWriter, buffer: []const u8) !usize {
            std.debug.assert(std.mem.indexOfAny(u8, buffer, forbidden_chars) == null);

            var written: usize = 0;

            while (written < buffer.len) {
                if (cw.start_of_line) {
                    cw.start_of_line = false;
                    try cw.buffered_writer.writer().writeBytesNTimes(cw.indent_with, cw.indent_level);
                }

                const maybe_index = std.mem.indexOfPos(u8, buffer, written, "\n");
                if (maybe_index) |index| {
                    written += try cw.buffered_writer.write(buffer[written .. index + EOL.len]);
                    cw.start_of_line = true;
                } else {
                    written += try cw.buffered_writer.write(buffer[written..]);
                }
            }

            return written;
        }

        pub fn print(cw: *CWriter, comptime fmt: []const u8, args: anytype) !void {
            try cw.writer().print(fmt, args);
        }

        pub fn println(cw: *CWriter, comptime fmt: []const u8, args: anytype) !void {
            try cw.writer().print(fmt ++ EOL, args);
        }

        pub fn write(cw: *CWriter, raw: []const u8) !void {
            try cw.writer().writeAll(raw);
        }

        pub fn writeln(cw: *CWriter, raw: []const u8) !void {
            try cw.writer().writeAll(raw);
            try cw.writer().writeAll(EOL);
        }
    };
}

test CodeWriter {
    var list: std.ArrayList(u8) = .init(std.testing.allocator);
    defer list.deinit();

    var cw: CodeWriter(std.ArrayList(u8).Writer) = .init(list.writer());

    try cw.println("Hello, World!", .{});

    {
        cw.indent();
        defer cw.dedent();

        try cw.write("This");
        try cw.write(" is");
        try cw.write(" indented!");
        try cw.write("\nthis here as well!");
    }
    try cw.write("\nThis is regular level");

    try cw.flush();

    try std.testing.expectEqualStrings(
        \\Hello, World!
        \\    This is indented!
        \\    this here as well!
        \\This is regular level
    ,
        list.items,
    );
}
