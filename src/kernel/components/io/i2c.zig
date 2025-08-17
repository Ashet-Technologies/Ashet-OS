const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.i2c);

pub const BusID = ashet.abi.io.i2c.BusID;

pub const ExecuteCall = ashet.abi.io.i2c.Execute;

pub const Operation = ashet.abi.io.i2c.Operation;

/// The raw driver device.
pub const Device = struct {
    vtable: *const VTable,
    supports_10_bit_addressing: bool,

    pub const VTable = struct {
        begin_read_fn: *const fn (*Device, addr: u10, buffer: []u8) error{Busy}!void,
        begin_write_fn: *const fn (*Device, addr: u10, buffer: []const u8) error{Busy}!void,

        get_result_fn: *const fn (*Device) ?Result,
    };

    pub const Result = struct {
        @"error": ashet.abi.io.i2c.Operation.Error,
        processed: usize,
    };

    pub fn begin_read(dev: *Device, addr: u10, buffer: []u8) error{Busy}!void {
        return dev.vtable.begin_read_fn(dev, addr, buffer);
    }

    pub fn begin_write(dev: *Device, addr: u10, buffer: []const u8) error{Busy}!void {
        return dev.vtable.begin_write_fn(dev, addr, buffer);
    }

    pub fn get_result(dev: *Device) ?Result {
        return dev.vtable.get_result_fn(dev);
    }
};

pub const Bus = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);

    system_resource: ashet.resources.SystemResource = .{ .type = .io_i2c_bus },

    device: *Device,

    pub const destroy = Destructor.destroy;

    pub fn open(id: BusID) error{ NotFound, SystemResources }!*Bus {
        const dri = try driver_from_id(id);
        std.debug.assert(dri.class == .i2c_device);

        const bus = ashet.memory.type_pool(Bus).alloc() catch return error.SystemResources;
        errdefer ashet.memory.type_pool(Bus).free(bus);

        bus.* = .{
            .device = &dri.class.i2c_device,
        };

        return bus;
    }

    fn _internal_destroy(bus: *Bus) void {
        // TODO: Fix i2c bus destruction
        ashet.memory.type_pool(Bus).free(bus);
    }
};

pub fn enumerate(maybe_list: ?[]BusID) usize {
    if (maybe_list) |list| {
        var iter = ashet.drivers.enumerate(.i2c_device);
        var cnt: u32 = 0;
        while (iter.next()) |dri| {
            if (cnt == list.len)
                break;
            // store the pointer to the driver as the bus id.
            // This allows us finding the right driver even if enumeration changes.
            list[cnt] = @enumFromInt(@intFromPtr(dri));
            cnt += 1;
        }
        std.debug.assert(cnt <= list.len);
        return cnt;
    } else {
        return ashet.drivers.get_available_count(.i2c_device);
    }
}

pub fn query_metadata(id: BusID, name_buf: ?[]u8) error{NotFound}!usize {
    const dri = try driver_from_id(id);

    return ashet.utils.copy_slice(u8, name_buf, dri.name);
}

fn driver_from_id(search_id: BusID) error{NotFound}!*ashet.drivers.Driver {
    var iter = ashet.drivers.enumerate(.i2c_device);
    while (iter.next()) |dri| {
        // store the pointer to the driver as the bus id.
        // This allows us finding the right driver even if enumeration changes.
        const this_id: BusID = @enumFromInt(@intFromPtr(dri));
        if (this_id == search_id)
            return ashet.drivers.resolveDriver(.i2c_device, dri);
    }
    return error.NotFound;
}

var work_queue: ashet.overlapped.WorkQueue = undefined;

pub fn execute_async(call: *ashet.overlapped.AsyncCall, inputs: ashet.abi.io.i2c.Execute.Inputs) void {
    const owner = call.resource_owner;

    const bus = ashet.resources.resolve(Bus, owner, inputs.bus.as_resource()) catch |err| {
        logger.warn("process {} used invalid file handle {}: {s}", .{ owner, inputs.bus, @errorName(err) });
        return call.finalize(ExecuteCall, error.InvalidHandle);
    };

    const addr_limit: u16 = if (bus.device.supports_10_bit_addressing)
        std.math.maxInt(u10)
    else
        std.math.maxInt(u7);

    // Check if all provided addresses are in the address range for
    // out target:
    for (inputs.sequence_ptr[0..inputs.sequence_len]) |*seq| {
        if (seq.address >= addr_limit) {
            logger.warn("detected invalid i2c address: 0x{X:0>2}", .{seq.address});
            return call.finalize(ExecuteCall, error.InvalidAddress);
        }
        if (ashet.abi.io.i2c.is_reserved_address(@intCast(seq.address))) {
            logger.warn("detected invalid i2c address: 0x{X:0>2}", .{seq.address});
            return call.finalize(ExecuteCall, error.InvalidAddress);
        }

        if (seq.type != .ping and seq.data_len == 0) {
            return call.finalize(ExecuteCall, error.EmptyOperation);
        }

        // Perform a sane initialization of the data:
        seq.@"error" = .aborted;
        seq.processed = 0;
    }

    if (inputs.sequence_len > 0) {
        work_queue.enqueue(call, bus);
    } else {
        // Immediate completion
        return call.finalize(ExecuteCall, .{ .count = 0 });
    }
}

var current_task: ?CurrentTask = null;

/// Proceeds the processing of I²C transfers
pub fn tick() void {
    while (true) {
        if (current_task == null) {
            const call, const bus_ptr = work_queue.dequeue() orelse return;

            const bus: *Bus = @ptrCast(@alignCast(bus_ptr));

            const inputs = call.arc.cast(ExecuteCall).inputs;

            logger.debug("start task ({} items)", .{inputs.sequence_len});

            current_task = .{
                .call = call,
                .bus = bus,
                .sequence = inputs.sequence_ptr[0..inputs.sequence_len],
                .index = 0,
            };
        }

        const task = &current_task.?;
        std.debug.assert(task.index < task.sequence.len);

        const op = &task.sequence[task.index];

        if (!task.op_started) {
            logger.debug("start op [{}] {s} => 0x{X:0>2}", .{ task.index, @tagName(op.type), op.address });
            const addr: u10 = @intCast(op.address);
            switch (op.type) {
                .ping => {
                    const Static = struct {
                        var dummy: [1]u8 = .{0};
                    };
                    // A ping is basically a read with one byte of dummy data
                    task.bus.device.begin_read(addr, &Static.dummy) catch |err| switch (err) {
                        error.Busy => @panic("race condition between different I2C components."),
                    };
                },
                .read => {
                    task.bus.device.begin_read(addr, op.data_ptr[0..op.data_len]) catch |err| switch (err) {
                        error.Busy => @panic("race condition between different I2C components."),
                    };
                },
                .write => {
                    task.bus.device.begin_write(addr, op.data_ptr[0..op.data_len]) catch |err| switch (err) {
                        error.Busy => @panic("race condition between different I2C components."),
                    };
                },
            }
            task.op_started = true;
        }

        std.debug.assert(task.op_started);

        // Fetch result or stop processing:
        const result = task.bus.device.get_result() orelse return;

        logger.debug("complete op [{}] {s}, err={s} / count={}", .{
            task.index,
            @tagName(op.type),
            @tagName(result.@"error"),
            result.processed,
        });

        op.@"error" = result.@"error";
        op.processed = if (op.type != .ping)
            result.processed
        else
            0;

        task.op_started = false;

        var completed: bool = false;
        handle: switch (op.@"error") {
            .none => {
                task.index += 1;
                if (task.index >= task.sequence.len) {
                    std.debug.assert(task.index == task.sequence.len);
                    completed = true;
                }
            },
            .device_not_found => if (op.type == .ping) {
                continue :handle .none;
            } else {
                completed = true;
            },
            else => {
                completed = true;
            },
        }

        if (completed) {
            logger.debug("complete task {}/{} items", .{
                task.index,
                task.sequence.len,
            });
            task.call.finalize(
                ashet.abi.io.i2c.Execute,
                .{ .count = task.index },
            );
            current_task = null;
        }
    }
}

const CurrentTask = struct {
    call: *ashet.overlapped.AsyncCall,
    bus: *Bus,

    sequence: []Operation,
    index: usize = 0,

    op_started: bool = false,
};
