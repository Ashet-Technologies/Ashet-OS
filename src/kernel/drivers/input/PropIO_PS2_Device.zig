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
slots: [4]Slot,

pub fn init(module: *propio.Module) !*PropIO_PS2_Device {
    const driver = try ashet.memory.type_pool(PropIO_PS2_Device).alloc();
    errdefer ashet.memory.type_pool(PropIO_PS2_Device).free(driver);

    driver.* = .{
        .slots = undefined,
    };

    driver.slots[0] = .{
        .index = 0,
        .module = module,
        .generic = .init(&driver.slots[0].data_source, &driver.slots[0].data_sink),
        .thread = try ashet.scheduler.Thread.spawn(Slot.work, &driver.slots[0], .{
            // TODO: Determine proper stack size here: .stack_size = 0,
        }),
    };
    errdefer driver.slots[0].thread.kill();

    driver.slots[1] = .{
        .index = 1,
        .module = module,
        .generic = .init(&driver.slots[1].data_source, &driver.slots[1].data_sink),
        .thread = try ashet.scheduler.Thread.spawn(Slot.work, &driver.slots[1], .{
            // TODO: Determine proper stack size here: .stack_size = 0,
        }),
    };
    errdefer driver.slots[1].thread.kill();

    driver.slots[2] = .{
        .index = 2,
        .module = module,
        .generic = .init(&driver.slots[2].data_source, &driver.slots[2].data_sink),
        .thread = try ashet.scheduler.Thread.spawn(Slot.work, &driver.slots[2], .{
            // TODO: Determine proper stack size here: .stack_size = 0,
        }),
    };
    errdefer driver.slots[2].thread.kill();

    driver.slots[3] = .{
        .index = 3,
        .module = module,
        .generic = .init(&driver.slots[3].data_source, &driver.slots[3].data_sink),
        .thread = try ashet.scheduler.Thread.spawn(Slot.work, &driver.slots[3], .{
            // TODO: Determine proper stack size here: .stack_size = 0,
        }),
    };
    errdefer driver.slots[3].thread.kill();

    for (driver.slots) |slot| {
        slot.thread.start() catch unreachable; // Thread is guaranteed to be stopped.
    }

    return driver;
}

fn process_fifo_data(dri: *propio.Device, fifo: propio.RxFifo, data: []const u8) void {
    const dev: *PropIO_PS2_Device = @fieldParentPtr("device", dri);

    switch (fifo) {
        .rx_fifo0 => dev.slots[0].process_fifo_data(data),
        .rx_fifo1 => dev.slots[1].process_fifo_data(data),
        .rx_fifo2 => dev.slots[2].process_fifo_data(data),
        .rx_fifo3 => dev.slots[3].process_fifo_data(data),
    }
}

const Slot = struct {
    index: u2,
    module: *propio.Module,
    thread: *ashet.scheduler.Thread,
    generic: Generic_PS2_Device,
    data_sink: Generic_PS2_Device.StreamSink = .{
        .write_fn = write_module_data,
    },
    data_source: Generic_PS2_Device.StreamSource = .{
        .read_available_fn = read_available_module_data,
    },
    inbound_data: std.fifo.LinearFifo(u8, .{ .Static = 16 }) = .init(),

    fn write_module_data(sink: *Generic_PS2_Device.StreamSink, data: []const u8, deadline: ashet.time.Deadline) error{Timeout}!void {
        const dev: *Slot = @fieldParentPtr("data_sink", sink);

        // PropIO is assumed to be blazingly fast:
        switch (dev.index) {
            0 => dev.module.send(.tx_fifo0, data),
            1 => dev.module.send(.tx_fifo1, data),
            2 => dev.module.send(.tx_fifo2, data),
            3 => dev.module.send(.tx_fifo3, data),
        }
        _ = deadline;
    }

    fn read_available_module_data(source: *Generic_PS2_Device.StreamSource, data: []u8) usize {
        const dev: *Slot = @fieldParentPtr("data_source", source);

        return dev.inbound_data.read(data);
    }

    fn process_fifo_data(slot: *Slot, data: []const u8) void {
        const writable = slot.inbound_data.writableLength();
        const written = @min(writable, data.len);
        if (written < data.len) {
            logger.err("PS/2 RX buffer overrun by {} bytes", .{data.len - written});
        }
        slot.inbound_data.writeAssumeCapacity(data[0..written]);
        // TODO: Wakeup PS/2 thread
    }

    fn work(dev_ptr: ?*anyopaque) callconv(.c) noreturn {
        const dev: *Slot = @ptrCast(@alignCast(dev_ptr.?));

        // spread the init sequence equally over a second, so we don't try to
        // execute everything at once
        {
            var deadline: ashet.time.Deadline = .init_rel(250 * @as(u32, dev.index));

            while (!deadline.is_reached()) {
                ashet.scheduler.yield();
            }
        }

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
};
