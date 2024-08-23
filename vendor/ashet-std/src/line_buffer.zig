const std = @import("std");

/// A type for performing line buffering.
pub fn LineBuffer(comptime length: usize) type {
    return struct {
        pub const capacity = length;

        buffer: [capacity]u8 = undefined,
        len: usize = 0,

        pub const Result = struct { usize, ?[]const u8 };
        pub fn append(buf: *@This(), string: []const u8) Result {
            const remaining_space = capacity - buf.len;
            const maybe_lf_index = std.mem.indexOfScalar(u8, string, '\n');
            const insert_len = if (maybe_lf_index) |lf_index|
                @min(remaining_space, lf_index)
            else
                @min(string.len, remaining_space);

            @memcpy(buf.buffer[buf.len..][0..insert_len], string[0..insert_len]);
            buf.len += insert_len;

            if (maybe_lf_index) |lf_index| {
                // we found a line feed, skip over LF:
                const result: Result = .{ lf_index + 1, buf.buffer[0..buf.len] };
                buf.len = 0;
                return result;
            } else if (buf.len == buf.buffer.len) {
                // we ran into the buffer limit, so consume what we inserted and also
                // drain the buffer:
                const result: Result = .{ insert_len, buf.buffer[0..buf.len] };
                buf.len = 0;
                return result;
            } else {
                // Neither we had a buffer overrun nor did we find a LF,
                // so we just append to the buffer:
                return .{ insert_len, null };
            }
        }
    };
}

test LineBuffer {
    var buffer: LineBuffer(16) = .{};

    {
        const consumed, const maybe_output = buffer.append("Hello, World!");
        try std.testing.expectEqual(13, consumed);
        try std.testing.expectEqual(13, buffer.len);
        try std.testing.expectEqual(null, maybe_output);
    }

    {
        const consumed, const maybe_output = buffer.append("\n");
        try std.testing.expectEqual(1, consumed);
        try std.testing.expectEqual(0, buffer.len);
        try std.testing.expectEqualStrings("Hello, World!", maybe_output.?);
    }

    {
        const consumed, const maybe_output = buffer.append("Line 1\nLine 2\n");
        try std.testing.expectEqual(7, consumed);
        try std.testing.expectEqual(0, buffer.len);
        try std.testing.expectEqualStrings("Line 1", maybe_output.?);
    }
}
