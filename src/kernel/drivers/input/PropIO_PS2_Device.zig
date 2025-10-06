//!
//! This is a driver for PS/2 devices running over PropIO.
//!
const std = @import("std");
const ashet = @import("../../main.zig");

const logger = std.log.scoped(.propio_ps2);
const propio = ashet.drivers.propio;

const Generic_PS2_Device = @import("Generic_PS2_Device.zig");

const PropIO_PS2_Device = @This();

device: propio.Device = .{
    .notify_fn = process_fifo_data,
},
generic: Generic_PS2_Device,
thread: *ashet.scheduler.Thread,
module: *propio.Module,
data_sink: Generic_PS2_Device.StreamSink = .{
    .write_fn = write_module_data,
},
data_source: Generic_PS2_Device.StreamSource = .{
    .read_available_fn = read_available_module_data,
},
inbound_data: std.fifo.LinearFifo(u8, .{ .Static = 16 }) = .init(),

pub fn init(module: *propio.Module) !*PropIO_PS2_Device {
    const driver = try ashet.memory.type_pool(PropIO_PS2_Device).alloc();
    errdefer ashet.memory.type_pool(PropIO_PS2_Device).free(driver);

    driver.* = .{
        .generic = .init(&driver.data_source, &driver.data_sink),
        .thread = try ashet.scheduler.Thread.spawn(work, driver, .{
            // TODO: Determine proper stack size here: .stack_size = 0,
        }),
        .module = module,
    };

    driver.thread.start() catch unreachable; // Thread is guaranteed to be stopped.

    return driver;
}

fn work(dev_ptr: ?*anyopaque) callconv(.c) noreturn {
    const dev: *PropIO_PS2_Device = @ptrCast(@alignCast(dev_ptr.?));

    while (true) {
        // Reset the driver FIFO before each restart, so we don't have spurious data which
        // will hang the driver on a crash.
        dev.inbound_data = .init();

        dev.generic.run() catch |err| {
            logger.err("PS/2 driver crashed: {s}", .{@errorName(err)});
        };

        var deadline: ashet.time.Deadline = .init_rel(1000);

        while (!deadline.is_reached()) {
            ashet.scheduler.yield();
        }
    }
}

fn process_fifo_data(dri: *propio.Device, fifo: propio.RxFifo, data: []const u8) void {
    const dev: *PropIO_PS2_Device = @fieldParentPtr("device", dri);

    switch (fifo) {
        .rx_fifo0 => {
            const writable = dev.inbound_data.writableLength();
            const written = @min(writable, data.len);
            if (written < data.len) {
                logger.err("PS/2 RX buffer overrun by {} bytes", .{data.len - written});
            }
            dev.inbound_data.writeAssumeCapacity(data[0..written]);
            // TODO: Wakeup PS/2 thread
        },
        else => {
            logger.err("TODO: Properly implement Quad PS/2 driver!", .{});
            return;
        },
    }
}

fn write_module_data(sink: *Generic_PS2_Device.StreamSink, data: []const u8, deadline: ashet.time.Deadline) error{Timeout}!void {
    const dev: *PropIO_PS2_Device = @fieldParentPtr("data_sink", sink);

    // PropIO is assumed to be blazingly fast:
    dev.module.send(.tx_fifo0, data);
    _ = deadline;
}

fn read_available_module_data(source: *Generic_PS2_Device.StreamSource, data: []u8) usize {
    const dev: *PropIO_PS2_Device = @fieldParentPtr("data_source", source);

    return dev.inbound_data.read(data);
}
