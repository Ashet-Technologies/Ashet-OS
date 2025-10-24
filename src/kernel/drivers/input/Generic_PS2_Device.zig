//!
//! This driver implements a generic PS/2 device which can be either
//! a keyboard or a mouse.
//!
//! The driver performs device auto-detection and auto-configuration.
//!
const std = @import("std");
const ashet = @import("../../main.zig");
const ps2 = @import("ps2.zig");

const logger = std.log.scoped(.generic_ps2);

const Driver = ashet.drivers.Driver;
const Deadline = ashet.time.Deadline;

const Generic_PS2_Device = @This();

const KeyUsageCode = ashet.abi.KeyUsageCode;

driver: Driver = .{
    .name = "Generic PS/2 Device",
    .class = .{
        .input = .{
            .pollFn = poll,
        },
    },
},

input: *StreamSource,
output: *StreamSink,

const IO_Error = error{ NoAcknowledge, Timeout, DeviceError };

fn poll(driver: *Driver) void {
    const dev: *Generic_PS2_Device = @fieldParentPtr("driver", driver);
    _ = dev;
}

pub fn init(
    input: *StreamSource,
    output: *StreamSink,
) Generic_PS2_Device {
    return .{
        .input = input,
        .output = output,
    };
}

pub fn run(dri: *Generic_PS2_Device) (error{NoDevice} || IO_Error)!void {
    logger.debug("reset device...", .{});
    dri.write_command(.reset, .from_ms(1000)) catch |err| switch (err) {
        error.Timeout => return error.NoDevice,
        error.NoAcknowledge, error.DeviceError => |e| return e,
    };

    const reset_resp = try dri.read_byte(.from_ms(1000));
    logger.debug("response to reset: 0x{X:0>2}", .{reset_resp});

    dri.drain(.from_ms(10));

    logger.debug("detect device type...", .{});
    const maybe_device_type = try dri.detect_device_type(.from_ms(1000));
    const device_type = maybe_device_type orelse {
        logger.err("could not determine device type!", .{});
        return;
    };

    logger.info("detected PS/2 device of type {}", .{device_type});

    if (device_type.isMouse()) {
        try dri.handle_mouse();
    } else if (device_type.isKeyboard()) {
        try dri.handle_keyboard();
    } else {
        logger.err("unsupported device type: {}", .{device_type});
    }
}

fn handle_mouse(dri: *Generic_PS2_Device) IO_Error!void {
    const init_deadline: Deadline = .from_ms(2500);
    try dri.write_command(.set_defaults, init_deadline);
    try dri.write_command(.enable_scanning, init_deadline);

    // TODO: Here, we should switch over to interrupt driven mode on x86!

    var decoder: ps2.MouseDecoder = .{};

    while (true) {
        const byte = try dri.read_byte(.infinite);

        decoder.push(byte) catch |err| switch (err) {
            // can't overrun as we push one byte, and process all generated
            // events. a single byte can only generate up to 3 events and the
            // queue is 4 events long.
            error.Overrun => unreachable,
        };

        while (decoder.pull()) |event| {
            logger.debug("mouse event: {}", .{event});
            ashet.input.push_raw_event(event);
        }
    }
}

fn handle_keyboard(dri: *Generic_PS2_Device) IO_Error!void {
    const init_deadline: Deadline = .from_ms(3000);

    try dri.write_command(.set_defaults, init_deadline);

    try dri.write_command(Keyboard.select_scancode_set, init_deadline);
    try dri.write_byte(0x01, init_deadline); // select scancode set 1

    try dri.write_command(Keyboard.select_scancode_set, init_deadline);
    try dri.write_byte(0x00, init_deadline); // get scancode set
    const scancode_ack = try dri.read_byte(init_deadline);
    if (scancode_ack != 0xFA) {
        logger.warn("scancode set query failed: 0x{X:0>2}", .{scancode_ack});
        while (true) {
            const byte = try dri.read_byte(.infinite);
            logger.warn("unsupported keyboard byte 0x{X:0>}", .{byte});
        }
        unreachable;
    }

    const scancode_set = try dri.read_byte(init_deadline);
    logger.info("keyboard uses active scancode set: 0x{X:0>2}", .{scancode_set});

    switch (scancode_set) {
        inline 1, 2, 3 => |scs| {

            // TODO: Here, we should switch over to interrupt driven mode on x86!

            var decoder = switch (scs) {
                1 => ps2.KeyboardDecoderSCS1{},
                2 => ps2.KeyboardDecoderSCS2{},
                3 => @panic("unsupported scan code set 3"),
                else => unreachable,
            };

            while (true) {
                const byte = try dri.read_byte(.infinite);

                decoder.push(byte) catch |err| switch (err) {
                    // can't overrun as we push one byte, and process all generated
                    // events. a single byte can only generate up to 1 event and the
                    // queue is 4 events long.
                    error.Overrun => unreachable,
                };

                while (decoder.pull()) |event| {
                    logger.debug("keyboard event: {}", .{event});
                    ashet.input.push_raw_event(event);
                }
            }
        },

        else => {
            logger.warn("unsupported scancode set: 0x{X:0>2}", .{scancode_ack});
            while (true) {
                const byte = try dri.read_byte(.infinite);
                logger.warn("unsupported keyboard byte 0x{X:0>}", .{byte});
            }
            unreachable;
        },
    }
}

fn drain(dri: Generic_PS2_Device, timeout: Deadline) void {
    while (true) {
        while (dri.read_byte(timeout)) |byte| {
            logger.debug("draining 0x{X:0>2}", .{byte});
        } else |err| switch (err) {
            error.Timeout => break,
        }
    }
}

fn detect_device_type(dri: Generic_PS2_Device, timeout: Deadline) !?ps2.DeviceType {
    try dri.write_command(.disable_scanning, timeout);
    try dri.write_command(.identify, timeout);

    const lo = dri.read_byte(timeout) catch return null;
    const hi = dri.read_byte(timeout) catch 0x00;

    const device_id = std.mem.readInt(u16, &.{ lo, hi }, .little);

    return @enumFromInt(device_id);
}

fn read_byte(dri: Generic_PS2_Device, timeout: Deadline) error{Timeout}!u8 {
    var data: [1]u8 = undefined;
    try dri.input.read_all(&data, timeout);
    return data[0];
}

fn write_byte(dri: Generic_PS2_Device, data: u8, timeout: Deadline) error{Timeout}!void {
    try dri.output.write(&.{data}, timeout);
}

fn write_command(dri: Generic_PS2_Device, cmd: Command, timeout: Deadline) IO_Error!void {
    for (0..3) |_| {
        logger.debug("write {}", .{cmd});
        try dri.write_byte(@intFromEnum(cmd), timeout);

        const response: Response = @enumFromInt(try dri.read_byte(timeout));
        logger.debug("  got {}", .{response});

        switch (response) {
            .ack => return,
            .resend => {
                continue;
            },
            else => return error.NoAcknowledge,
        }
    }

    // This is actually a device error as we didn't receive either ACK or RESEND, but we also didn't timeout
    return error.DeviceError;
}

pub const Command = enum(u8) {
    identify = 0xF2,
    enable_scanning = 0xF4,
    disable_scanning = 0xF5,
    set_defaults = 0xF6,
    resend = 0xFE,
    reset = 0xFF,

    _,
};

pub const Response = enum(u8) {
    ack = 0xFA,
    resend = 0xFE,

    _,
};

const Keyboard = struct {
    pub const set_leds: Command = @enumFromInt(0xED);
    pub const selftest: Command = @enumFromInt(0xEE); // returns 0xEE
    pub const select_scancode_set: Command = @enumFromInt(0xF0);
    pub const set_repeat_rate: Command = @enumFromInt(0xF3);
};

const Mouse = struct {
    pub const set_resolution: Command = @enumFromInt(0xE8);
    pub const status_request: Command = @enumFromInt(0xE9);
    pub const request_single_packet: Command = @enumFromInt(0xEB);
    pub const get_mouse_id: Command = @enumFromInt(0xF2);
    pub const set_sample_rate: Command = @enumFromInt(0xF3);
};

// TODO: Refactor sink/source and move them elsewhere:

pub const StreamSink = struct {
    write_fn: *const fn (*StreamSink, []const u8, Deadline) error{Timeout}!void,

    pub fn write(sink: *StreamSink, data: []const u8, deadline: Deadline) error{Timeout}!void {
        return sink.write_fn(sink, data, deadline);
    }
};

pub const StreamSource = struct {
    read_available_fn: *const fn (*StreamSource, []u8) usize,
    // TODO: Introduce a read_all_fn which takes a deadline for more efficient backing impls

    pub fn read_available(source: *StreamSource, data: []u8) usize {
        return source.read_available_fn(source, data);
    }

    pub fn read_all(source: *StreamSource, data: []u8, deadline: Deadline) error{Timeout}!void {
        var offset: usize = 0;
        while (offset < data.len) {
            const len = source.read_available(data[offset..]);
            offset += len;
            if (offset == data.len)
                break;

            try deadline.check();

            ashet.scheduler.yield(); // TODO: Is this okay?
        }
    }
};
