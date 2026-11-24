const std = @import("std");

/// Unbuffered formatting over a byte callback, using the std.Io.Writer interface.
pub fn CallbackWriter(comptime Context: type, comptime Error: type, comptime write_fn: fn (Context, []const u8) Error!usize) type {
    return struct {
        context: Context,
        const Self = @This();

        pub fn writeAll(self: Self, bytes: []const u8) Error!void {
            var index: usize = 0;
            while (index < bytes.len) index += try write_fn(self.context, bytes[index..]);
        }

        pub fn print(self: Self, comptime format: []const u8, args: anytype) Error!void {
            var sink: Sink = .{ .context = self.context };
            sink.interface.print(format, args) catch return sink.err.?;
        }

        const Sink = struct {
            context: Context,
            err: ?Error = null,
            interface: std.Io.Writer = .{ .buffer = &.{}, .vtable = &.{ .drain = drain } },

            fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
                const sink: *Sink = @fieldParentPtr("interface", w);
                const writer: Self = .{ .context = sink.context };
                var count: usize = 0;
                for (data[0 .. data.len - 1]) |bytes| {
                    writer.writeAll(bytes) catch |err| {
                        sink.err = err;
                        return error.WriteFailed;
                    };
                    count += bytes.len;
                }
                for (0..splat) |_| {
                    writer.writeAll(data[data.len - 1]) catch |err| {
                        sink.err = err;
                        return error.WriteFailed;
                    };
                    count += data[data.len - 1].len;
                }
                return count;
            }
        };
    };
}
