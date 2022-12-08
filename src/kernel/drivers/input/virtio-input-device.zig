const std = @import("std");
const ashet = @import("root");
const logger = std.log.scoped(.@"virtio-input-device");
const virtio = @import("virtio");

const queue_size = 8;

const eventq = 0;
const statusq = 1;

fn selectConfig(regs: *volatile virtio.ControlRegs, select: virtio.input.ConfigSelect, subsel: virtio.input.ConfigEvSubSel) void {
    regs.device.input.select = select;
    regs.device.input.subsel = subsel;
}

fn initialize(regs: *volatile virtio.ControlRegs) !void {
    logger.info("initializing input device {*}", .{regs});

    const input_dev = &regs.device.input;

    _ = try regs.negotiateFeatures(virtio.FeatureFlags.any_layout | virtio.FeatureFlags.version_1);

    selectConfig(regs, .id_name, .unset);

    var copy = input_dev.data.string;
    logger.info("input: {s}", .{@as([]const u8, std.mem.sliceTo(&copy, 0))});

    selectConfig(regs, .ev_bits, .cess_key);
    var keys: u32 = 0;

    if (input_dev.select != .unset) {
        var i: u16 = 0;
        while (i < @as(u16, input_dev.size) * 8) : (i += 1) {
            if (input_dev.data.isBitSet(i)) {
                keys += 1;
            }
        }
        logger.info("keys = {}", .{keys});
    }

    selectConfig(regs, .ev_bits, .cess_rel);
    var axes: c_int = 0;
    var mouse_axes = false;

    if (input_dev.select != .unset) {
        var i: u16 = 0;
        while (i < @as(u16, input_dev.size) * 8) : (i += 1) {
            if (input_dev.data.isBitSet(i)) {
                axes += 1;
            }
        }
        logger.info("rel axes = {}", .{axes});

        if (axes != 0) {
            mouse_axes = (input_dev.data.bitmap[0] & 3) == 3;
        }
    }

    selectConfig(regs, .ev_bits, .cess_abs);
    var tablet_axes = false;

    if (input_dev.select != .unset) {
        var i: u16 = 0;
        while (i < @as(u16, input_dev.size) * 8) : (i += 1) {
            if (input_dev.data.isBitSet(i)) {
                axes += 1;
            }
        }
        logger.info("abs axes = {}", .{axes});

        if (axes != 0) {
            tablet_axes = (input_dev.data.bitmap[0] & 3) == 3;
        }
    }

    if (axes == 0 and keys >= 80) {
        try initDevice(regs, .keyboard);
    } else if (mouse_axes) {
        try initDevice(regs, .mouse);
    } else if (tablet_axes) {
        try initDevice(regs, .tablet);
    } else {
        logger.warn("Ignoring this device, it has unknown metrics", .{});
    }
}

pub const DeviceType = enum {
    keyboard,
    mouse,
    tablet,
};

const Device = struct {
    regs: *volatile virtio.ControlRegs,
    kind: DeviceData,

    events: [queue_size]virtio.input.Event,
    vq: virtio.queue.VirtQ(queue_size),
};

const DeviceData = union(DeviceType) {
    keyboard,
    mouse,
    tablet: Tablet,
};

const Tablet = struct {
    axis_min: [3]u32,
    axis_max: [3]u32,
};

var devices = std.BoundedArray(Device, 8){};

fn initDevice(regs: *volatile virtio.ControlRegs, device_type: DeviceType) !void {
    logger.info("recognized 0x{X:0>8} as {s}", .{ @ptrToInt(regs), @tagName(device_type) });

    const device = try devices.addOne();
    errdefer _ = devices.pop();

    device.* = Device{
        .regs = regs,
        .kind = undefined,
        .events = std.mem.zeroes([queue_size]virtio.input.Event),
        .vq = undefined,
    };

    try device.vq.init(eventq, regs);

    for (device.events) |*event| {
        device.vq.pushDescriptor(virtio.input.Event, event, .write, true, true);
    }

    switch (device_type) {
        .keyboard => {
            device.kind = DeviceData{ .keyboard = {} };
        },

        .mouse => {
            device.kind = DeviceData{ .mouse = {} };
        },

        .tablet => {
            @panic("tablet not supported yet");
            // device.kind = DeviceData{
            //     .tablet = .{
            //         .axis_min = undefined,
            //         .axis_max = undefined,
            //     },
            // };

            // for ([3]u8{ 0x00, 0x01, 0x02 }) |axis| {
            //     selectConfig(regs, .abs_info, @intToEnum(virtio.input.ConfigEvSubSel, axis));
            //     // if (regs.device.input.select == .unset) {
            //     //     return error.AxisInfoError;
            //     // }

            //     // device.kind.tablet.axis_min[axis] = input_dev.data.abs.min;
            //     // device.kind.tablet.axis_max[axis] = input_dev.data.abs.max;
            // }
        },
    }

    selectConfig(regs, .unset, .unset);

    regs.status |= virtio.DeviceStatus.driver_ok;

    device.vq.exec();
}

fn getDeviceEvent(dev: *Device) ?virtio.input.Event {
    const ret = dev.vq.singlePollUsed() orelse return null;

    const evt = dev.events[ret % queue_size];
    dev.vq.avail_i += 1;
    dev.vq.exec();

    return evt;
}

fn mapToMouseButton(val: u16) ?ashet.abi.MouseButton {
    return switch (val) {
        272 => .left,
        273 => .right,
        274 => .middle,
        275 => .nav_previous,
        276 => .nav_next,
        337 => .wheel_up,
        336 => .wheel_down,
        else => null,
    };
}

pub fn poll() void {
    for (devices.slice()) |*device| {
        device_fetch: while (true) {
            const evt = getDeviceEvent(device) orelse break :device_fetch;
            const event_type = @intToEnum(virtio.input.ConfigEvSubSel, evt.type);

            switch (device.kind) {
                .keyboard => {
                    switch (event_type) {
                        .unset => {},
                        .cess_key => ashet.input.pushRawEvent(.{ .keyboard = .{
                            .scancode = evt.code,
                            .down = evt.value != 0,
                        } }),
                        else => logger.warn("unhandled keyboard event: {}", .{event_type}),
                    }
                },
                .mouse => {
                    switch (event_type) {
                        .unset => {},
                        .cess_key => {
                            ashet.input.pushRawEvent(.{ .mouse_button = .{
                                .button = mapToMouseButton(evt.code) orelse continue,
                                .down = (evt.value != 0),
                            } });
                        },
                        .cess_rel => {
                            if (evt.code == 0) {
                                ashet.input.pushRawEvent(.{ .mouse_motion = .{
                                    .dx = @bitCast(i32, evt.value),
                                    .dy = 0,
                                } });
                            } else if (evt.code == 1) {
                                ashet.input.pushRawEvent(.{ .mouse_motion = .{
                                    .dx = 0,
                                    .dy = @bitCast(i32, evt.value),
                                } });
                            }
                        },
                        else => logger.warn("unhandled mouse event: {}", .{event_type}),
                    }
                },
                else => logger.warn("unhandled event for {s} device: {}", .{ @tagName(device.kind), event_type }),
            }
        }
    }
}
