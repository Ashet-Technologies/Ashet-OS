const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.rp2xxx_i2c_device);

const rp2350 = @import("rp2350");
const hal = @import("rp2350-hal");
const regz = rp2350.peripherals;

const Driver = ashet.drivers.Driver;
const I2C_Device = ashet.drivers.I2C_Device;
const RP2xxx_I2C_Device = @This();

const Result = struct {
    @"error": ?hal.i2c.TransactionError,
    size: usize,
};

const default_timeout = 1000; // ms

driver: Driver = .{
    .name = "RP2xxx I²C",
    .class = .{
        .i2c_device = .{
            .supports_10_bit_addressing = false, // TODO: This might be possible?
            .vtable = &.{
                .begin_read_fn = begin_read,
                .begin_write_fn = begin_write,
                .get_result_fn = get_result,
            },
        },
    },
},

i2c: hal.i2c.I2C,
last_op: ?Result,

pub fn init(comptime clock_config: hal.clocks.config.Global, i2c: hal.i2c.I2C) !RP2xxx_I2C_Device {
    i2c.apply(.{
        .clock_config = clock_config,
        .repeated_start = true,
        .baud_rate = 100_000,
    });

    return .{
        .i2c = i2c,
        .last_op = null,
    };
}

pub fn begin_read(dev_ptr: *I2C_Device, addr: u10, buffer: []u8) error{Busy}!void {
    const driver = from_device(dev_ptr);
    if (driver.last_op != null)
        return error.Busy;

    const i2c_addr: hal.i2c.Address = .new(@intCast(addr)); // TODO: Fix for 10 bit addressing!

    const err: ?hal.i2c.TransactionError = if (driver.i2c.read_blocking(i2c_addr, buffer, default_timeout)) |_|
        null
    else |err|
        err;
    driver.last_op = .{
        .@"error" = err,
        .size = buffer.len,
    };
}

pub fn begin_write(dev_ptr: *I2C_Device, addr: u10, buffer: []const u8) error{Busy}!void {
    const driver = from_device(dev_ptr);
    if (driver.last_op != null)
        return error.Busy;

    const i2c_addr: hal.i2c.Address = .new(@intCast(addr)); // TODO: Fix for 10 bit addressing!

    const err: ?hal.i2c.TransactionError = if (driver.i2c.write_blocking(i2c_addr, buffer, default_timeout)) |_|
        null
    else |err|
        err;
    driver.last_op = .{
        .@"error" = err,
        .size = buffer.len,
    };
}

pub fn get_result(dev_ptr: *I2C_Device) ?ashet.io.i2c.Device.Result {
    const driver = from_device(dev_ptr);

    const op = driver.last_op orelse return null;
    driver.last_op = null;

    return .{
        .@"error" = if (op.@"error") |err| switch (err) {
            error.DeviceNotPresent => .device_not_found,
            error.NoAcknowledge => .no_acknowledge,
            error.Timeout => .timeout,
            error.NoData => unreachable,
            error.TargetAddressReserved, error.TxFifoFlushed, error.UnknownAbort => blk: {
                logger.err("i2c hardware failure: {s}", .{@errorName(err)});
                break :blk .fault;
            },
        } else .none,
        .processed = op.size,
    };
}

fn from_device(dev: *I2C_Device) *RP2xxx_I2C_Device {
    const dri = ashet.drivers.resolveDriver(.i2c_device, dev);
    return ashet.drivers.Driver.resolve(dri, RP2xxx_I2C_Device, "driver");
}
