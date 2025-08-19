const std = @import("std");
const rp2350 = @import("rp2350-hal");

const ChunkingWriter = @This();

const Error = rp2350.uart.UART.Writer.Error;
const Writer = std.io.Writer(*ChunkingWriter, Error, write);

const chunk_size = 50;

uart: rp2350.uart.UART,
offset: usize = 0,

pub fn writer(cw: *ChunkingWriter) Writer {
    return .{ .context = cw };
}

fn write(cw: *ChunkingWriter, all_data: []const u8) Error!usize {
    var data = all_data;

    while (data.len > 0) {
        const remaining = chunk_size - cw.offset;
        const written = @min(data.len, remaining);
        cw.offset += written;

        try cw.uart.write_blocking(data[0..written], .no_deadline);
        if (cw.offset == chunk_size) {
            try cw.uart.write_blocking("\r> ", .no_deadline);
            cw.offset = 0;
        }

        data = data[written..];
    }
    return all_data.len;
}
