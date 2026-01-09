const std = @import("std");
const ashet = @import("../../../../../main.zig");
const logger = std.log.scoped(.nested_i2c_device);

const rp2350 = @import("rp2350");
const hal = @import("rp2350-hal");
const regz = rp2350.peripherals;

const Driver = ashet.drivers.Driver;
const I2C_Device = ashet.drivers.I2C_Device;
const RP2xxx_I2C_Device = @This();

const Result = ashet.io.i2c.Device.Result;

const default_timeout: @import("microzig").drivers.time.Duration = .from_ms(1000);

driver: Driver = .{
    .name = "Ashet I2C",
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
mux: hal.i2c.Address,
mask: u8,
last_op: ?Result,

const Config = struct {
    clock_config: hal.clocks.config.Global,
    i2c: hal.i2c.I2C,
    mux: hal.i2c.Address,
    mask: u8,
    name: []const u8,
};

pub fn init(comptime config: Config) !RP2xxx_I2C_Device {
    config.i2c.apply(.{
        .clock_config = config.clock_config,
        .repeated_start = true,
        .baud_rate = 100_000,
    });

    var dev: RP2xxx_I2C_Device = .{
        .i2c = config.i2c,
        .mask = config.mask,
        .mux = config.mux,
        .last_op = null,
    };
    dev.driver.name = config.name;
    return dev;
}

fn setup_mux(driver: *RP2xxx_I2C_Device) bool {
    driver.i2c.write_blocking(driver.mux, &.{driver.mask}, default_timeout) catch |err| {
        logger.err("failed to update internal bus switch: {s}!", .{@errorName(err)});
        driver.last_op = .{
            .@"error" = .fault,
            .processed = 0,
        };
        return false;
    };
    return true;
}

fn begin_read(dev_ptr: *I2C_Device, addr: u10, buffer: []u8) error{Busy}!void {
    const driver = from_device(dev_ptr);
    if (driver.last_op != null)
        return error.Busy;

    const i2c_addr: hal.i2c.Address = .new(@intCast(addr)); // TODO: Fix for 10 bit addressing!

    if (!driver.setup_mux())
        return;

    const err = map_err(driver.i2c.read_blocking(i2c_addr, buffer, default_timeout));
    driver.last_op = .{
        .@"error" = err,
        .processed = buffer.len,
    };
}

fn begin_write(dev_ptr: *I2C_Device, addr: u10, buffer: []const u8) error{Busy}!void {
    const driver = from_device(dev_ptr);
    if (driver.last_op != null)
        return error.Busy;

    const i2c_addr: hal.i2c.Address = .new(@intCast(addr)); // TODO: Fix for 10 bit addressing!

    if (!driver.setup_mux())
        return;

    const err = map_err(driver.i2c.write_blocking(i2c_addr, buffer, default_timeout));
    driver.last_op = .{
        .@"error" = err,
        .processed = buffer.len,
    };
}

fn get_result(dev_ptr: *I2C_Device) ?ashet.io.i2c.Device.Result {
    const driver = from_device(dev_ptr);

    const op = driver.last_op orelse return null;
    driver.last_op = null;

    return op;
}

fn from_device(dev: *I2C_Device) *RP2xxx_I2C_Device {
    const dri = ashet.drivers.resolveDriver(.i2c_device, dev);
    return ashet.drivers.Driver.resolve(dri, RP2xxx_I2C_Device, "driver");
}

fn map_err(result: hal.i2c.Error!void) ashet.abi.io.i2c.Operation.Error {
    return if (result) |_|
        .none
    else |err| switch (err) {
        error.DeviceNotPresent => .device_not_found,
        error.NoAcknowledge => .no_acknowledge,
        error.Timeout => .timeout,
        error.NoData => unreachable,
        error.TargetAddressReserved, error.TxFifoFlushed, error.UnknownAbort => blk: {
            logger.err("i2c hardware failure: {s}", .{@errorName(err)});
            break :blk .fault;
        },
    };
}
