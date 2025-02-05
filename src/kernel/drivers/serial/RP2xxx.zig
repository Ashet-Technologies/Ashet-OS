//! RaspberryPi RP2020 and RP2350 UART
const std = @import("std");
const ashet = @import("../../main.zig");
const Driver = ashet.drivers.Driver;
const hal = @import("rp2350-hal");

const RP2xxx = @This();

const WriteMode = ashet.drivers.SerialPort.WriteMode;

driver: Driver,
device: hal.uart.UART,

pub fn init(comptime clock_config: hal.clocks.config.Global, id: hal.uart.UART) !RP2xxx {
    id.apply(.{
        .baud_rate = 115_200,
        .clock_config = clock_config,
    });

    return .{
        .driver = .{
            .name = switch (id) {
                hal.uart.instance.UART0 => "RP2xxx UART0",
                hal.uart.instance.UART1 => "RP2xxx UART1",
                _ => unreachable,
            },
            .class = .{
                .serial = .{
                    .writeFn = writeSome,
                },
            },
        },
        .device = id,
    };
}

fn instance(dri: *Driver) *RP2xxx {
    return @fieldParentPtr("driver", dri);
}

fn writeSome(dri: *Driver, msg: []const u8, mode: WriteMode) usize {
    const dev = instance(dri);

    switch (mode) {
        .blocking => dev.device.write_blocking(msg, null) catch @panic("failed to write uart"),

        .only_fifo => for (msg, 0..) |char, i| {
            if (!dev.device.is_writeable())
                return i;
            dev.device.write_blocking(&.{char}, null) catch @panic("failed to write uart");
        },
    }

    return msg.len;
}
