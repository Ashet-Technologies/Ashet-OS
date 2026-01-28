//!
//! This program demonstrates the I²C capabilities of Ashet OS by
//! performing a full scan of all available I²C busses and printing
//! the results to the debug log.
//!

const std = @import("std");
const ashet = @import("ashet");

const i2c = ashet.abi.io.i2c;

pub const std_options = ashet.core.std_options;
pub const panic = ashet.core.panic;
comptime {
    _ = ashet.core;
}

pub fn main() !void {
    var bus_list: [32]i2c.BusID = undefined;

    const bus_count = i2c.enumerate(&bus_list);

    for (bus_list[0..bus_count]) |bus_id| {
        var bus_name_buf: [256]u8 = @splat(0);

        const bus_name_len = try i2c.query_metadata(bus_id, &bus_name_buf);
        std.log.info("I²C Bus \"{f}\" ({})", .{
            std.zig.fmtString(bus_name_buf[0..bus_name_len]),
            bus_id,
        });

        const bus = try i2c.open(bus_id);
        defer ashet.abi.resources.release(bus.as_resource());

        std.log.info("     | 0 1 2 3 4 5 6 7 8 9 A B C D E F |", .{});

        var addr: u16 = 0;
        var pings: [16]i2c.Operation = undefined;
        while (addr < 128) : (addr += pings.len) {
            const has_reserved = for (addr..addr + pings.len) |a| {
                if (i2c.is_reserved_address(@intCast(a)))
                    break true;
            } else false;

            // Initialize all "row pings"
            for (&pings, 0..) |*ping, i| {
                ping.* = .{
                    .type = .ping,
                    .address = @intCast(addr + i),
                    .data_ptr = &.{},
                    .data_len = 0,
                    .processed = 0,
                    .@"error" = .none,
                };
            }

            if (has_reserved) {
                for (&pings) |*ping| {
                    if (i2c.is_reserved_address(@intCast(ping.address))) {
                        ping.@"error" = .fault;
                        continue;
                    }

                    var scan_op: i2c.Execute = .init(bus, ping[0..1]);

                    try ashet.overlapped.singleShot(&scan_op);
                }
            } else {
                var scan_op: i2c.Execute = .init(bus, &pings);

                try ashet.overlapped.singleShot(&scan_op);
            }

            var row_buf: [256]u8 = undefined;
            var writer: std.Io.Writer = .fixed(&row_buf);

            try writer.print("0x{x}_ |", .{addr >> 4});

            for (pings) |ping| {
                try writer.print(" {c}", .{
                    @as(u7, switch (ping.@"error") {
                        .none => 'X',
                        .device_not_found => ' ',
                        .no_acknowledge => '?',
                        .aborted => 'A',
                        .timeout => 'T',
                        .fault => 'F',
                    }),
                });
            }
            try writer.writeAll(" |");

            std.log.info("{s}", .{writer.buffered()});
        }
    }
}
