const std = @import("std");
const rp2350 = @import("rp2350-hal");

const ChunkingWriter = @This();

const Error = rp2350.uart.UART.Writer.Error;

pub const chunk_size = 50;

uart: rp2350.uart.UART,
offset: usize = 0,

writer: std.Io.Writer,

pub fn init(uart: rp2350.uart.UART, buffer: []u8) ChunkingWriter {
    return .{
        .uart = uart,
        .writer = .{
            .buffer = buffer,
            .vtable = comptime &.{
                .drain = drain,
            },
        },
    };
}

fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    const cw: *ChunkingWriter = @fieldParentPtr("writer", w);

    try cw.write(w.buffered());
    w.end = 0;

    var n: usize = 0;
    for (data[0 .. data.len - 1]) |slice| {
        try cw.write(slice);
        n += slice.len;
    }
    for (0..splat) |_| {
        try cw.write(data[data.len - 1]);
    }
    return n + splat * data[data.len - 1].len;
}

fn write(cw: *ChunkingWriter, all_data: []const u8) std.Io.Writer.Error!void {
    var data = all_data;

    while (data.len > 0) {
        const remaining = chunk_size - cw.offset;
        const written = @min(data.len, remaining);
        cw.offset += written;

        cw.uart.write_blocking(data[0..written], .no_deadline) catch |err| switch (err) {
            error.Timeout => unreachable,
        };
        if (cw.offset == chunk_size) {
            cw.uart.write_blocking("\r> ", .no_deadline) catch |err| switch (err) {
                error.Timeout => unreachable,
            };
            cw.offset = 0;
        }

        data = data[written..];
    }
}
