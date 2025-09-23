//!
//! This driver implements a generic PS/2 device which can be either
//! a keyboard or a mouse.
//!
//! The driver performs device auto-detection and auto-configuration.
//!
const std = @import("std");
const ashet = @import("../../main.zig");

const logger = std.log.scoped(.generic_ps2);

const Driver = ashet.drivers.Driver;
const Deadline = ashet.time.Deadline;

const Generic_PS2_Device = @This();

const ConfigFileIterator = ashet.utils.ConfigFileIterator;
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

pub fn run(dri: *Generic_PS2_Device) !void {
    logger.info("reset device...", .{});
    try dri.write_command(.reset, .from_ms(1000));

    const reset_resp = try dri.read_byte(.from_ms(1000));
    logger.info("response to reset: 0x{X:0>2}", .{reset_resp});

    dri.drain(.from_ms(10));

    logger.info("detect device type...", .{});
    const maybe_device_type = try dri.detect_device_type(.from_ms(1000));
    const device_type = maybe_device_type orelse {
        logger.err("could not determine device type!", .{});
        return;
    };

    logger.info("  device type = {}", .{device_type});

    if (device_type.isMouse()) {
        try dri.handle_mouse();
    } else if (device_type.isKeyboard()) {
        try dri.handle_keyboard();
    } else {
        logger.err("unsupported device type: {}", .{device_type});
    }
}

fn handle_mouse(dri: *Generic_PS2_Device) !void {
    const init_deadline: Deadline = .from_ms(2500);
    try dri.write_command(.set_defaults, init_deadline);
    try dri.write_command(.enable_scanning, init_deadline);

    // TODO: Here, we should switch over to interrupt driven mode on x86!

    var decoder: MouseDecoder = .{};

    while (true) {
        const byte = try dri.read_byte(.infinite);

        try decoder.push(byte);

        while (decoder.pull()) |event| {
            logger.debug("mouse event: {}", .{event});
            switch (event) {
                .rel_motion => |motion| {
                    ashet.input.push_raw_event(.{
                        .mouse_rel_motion = .{
                            .dx = motion.dx,
                            .dy = motion.dy,
                        },
                    });
                },
                .button => |button| {
                    ashet.input.push_raw_event(.{
                        .mouse_button = .{
                            .button = switch (button.button) {
                                .left => .left,
                                .right => .right,
                                .middle => .middle,
                            },
                            .down = button.down,
                        },
                    });
                },
            }
        }
    }
}

fn handle_keyboard(dri: *Generic_PS2_Device) !void {
    const init_deadline: Deadline = .from_ms(3000);

    try dri.write_command(.set_defaults, init_deadline);

    try dri.write_command(Keyboard.select_scancode_set, init_deadline);
    try dri.write_byte(0x01, init_deadline); // select scancode set 1

    try dri.write_command(Keyboard.select_scancode_set, init_deadline);
    try dri.write_byte(0x00, init_deadline); // get scancode set
    const scancode_ack = try dri.read_byte(init_deadline);
    if (scancode_ack != 0xFA) {
        logger.info("scancode set query failed: 0x{X:0>2}", .{scancode_ack});
        while (true) {
            const byte = try dri.read_byte(.infinite);
            logger.warn("unsupported keyboard byte 0x{X:0>}", .{byte});
        }
        unreachable;
    }

    const scancode_set = try dri.read_byte(init_deadline);
    logger.info("active scancode set: 0x{X:0>2}", .{scancode_set});

    switch (scancode_set) {
        inline 1, 2, 3 => |scs| {

            // TODO: Here, we should switch over to interrupt driven mode on x86!

            var decoder = switch (scs) {
                1 => KeyboardDecoderSCS1{},
                2 => KeyboardDecoderSCS2{},
                3 => @panic("unsupported scan code set 3"),
                else => unreachable,
            };

            while (true) {
                const byte = try dri.read_byte(.infinite);

                try decoder.push(byte);

                while (decoder.pull()) |event| {
                    logger.debug("keyboard event: {}", .{event});
                    ashet.input.push_raw_event(.{ .keyboard = event });
                }
            }
        },

        else => {
            logger.info("unsupported scancode set: 0x{X:0>2}", .{scancode_ack});
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

fn detect_device_type(dri: Generic_PS2_Device, timeout: Deadline) !?DeviceType {
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

fn write_command(dri: Generic_PS2_Device, cmd: Command, timeout: Deadline) error{ Timeout, NoResponse, NoAcknowledge }!void {
    for (0..3) |_| {
        logger.info("write {}", .{cmd});
        try dri.write_byte(@intFromEnum(cmd), timeout);

        const response: Response = @enumFromInt(try dri.read_byte(timeout));
        logger.info("  got {}", .{response});

        switch (response) {
            .ack => return,
            .resend => {
                continue;
            },
            else => return error.NoAcknowledge,
        }
    }

    return error.NoResponse;
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

pub const DeviceType = enum(u16) {
    standard_mouse = 0x00, // Standard PS/2 mouse
    wheel_mouse = 0x03, // Mouse with scroll wheel
    extended_mouse = 0x04, // 5-button mouse
    mf2_keyboard_v0 = 0x83AB, // MF2 keybaord
    mf2_keyboard_v1 = 0xC1AB, // MF2 keybaord
    short_keyboard = 0x84AB, // IBM ThinkPads, Spacesaver keyboards, many other "short" keyboards
    keyboard_ncd_97 = 0x85AB, // NCD N-97 keyboard, 122-Key Host Connect(ed) Keyboard
    keyboard_122 = 0x86AB, // 122-key keyboards
    jap_keyboard_g = 0x90AB, // Japanese "G" keyboards
    jap_keyboard_p = 0x91AB, // Japanese "P" keyboards
    jap_keyboard_a = 0x92AB, // Japanese "A" keyboards
    keyboard_ncd_sun = 0xA1AC, // NCD Sun layout keyboard

    unknown = 0xFFFF,
    _,

    pub fn isMouse(dt: DeviceType) bool {
        return switch (dt) {
            .standard_mouse => true,
            .wheel_mouse => true,
            .extended_mouse => true,
            else => false,
        };
    }

    pub fn isKeyboard(dt: DeviceType) bool {
        return switch (dt) {
            .mf2_keyboard_v0 => true,
            .mf2_keyboard_v1 => true,
            .short_keyboard => true,
            .keyboard_ncd_97 => true,
            .keyboard_122 => true,
            .jap_keyboard_g => true,
            .jap_keyboard_p => true,
            .jap_keyboard_a => true,
            .keyboard_ncd_sun => true,
            else => false,
        };
    }
};

const MouseEvent = union(enum) {
    button: struct {
        button: enum { left, middle, right },
        down: bool,
    },
    rel_motion: struct { dx: i16, dy: i16 },
};

const MouseDecoder = struct {
    state: State = .default,

    current: MouseHeader = MouseHeader{
        .left = false,
        .right = false,
        .middle = false,
        .x_sign = false,
        .y_sign = false,
        .x_overflow = false,
        .y_overflow = false,
    },

    queue: std.fifo.LinearFifo(MouseEvent, .{ .Static = 4 }) = .init(),

    pub fn drain(decoder: *MouseDecoder) void {
        while (decoder.pull()) |_| {}
    }

    pub fn push(decoder: *MouseDecoder, input: u8) error{Overrun}!void {
        switch (decoder.state) {
            .default => {
                const header = @as(MouseHeader, @bitCast(input));
                if (header.always_set) {
                    defer decoder.current = header;

                    if (header.left != decoder.current.left) {
                        decoder.queue.writeItem(.{
                            .button = .{ .button = .left, .down = header.left },
                        }) catch return error.Overrun;
                    }
                    if (header.right != decoder.current.right) {
                        decoder.queue.writeItem(.{
                            .button = .{ .button = .right, .down = header.right },
                        }) catch return error.Overrun;
                    }
                    if (header.middle != decoder.current.middle) {
                        decoder.queue.writeItem(.{
                            .button = .{ .button = .middle, .down = header.middle },
                        }) catch return error.Overrun;
                    }
                    decoder.state = .fetch_x;
                }
            },

            .fetch_x => {
                const dx = @as(i8, @bitCast(input));
                decoder.state = .{ .fetch_y = dx };
            },

            .fetch_y => |dx| {
                const dy = @as(i8, @bitCast(input));
                if ((dx != 0 or dy != 0) and !decoder.current.x_overflow and !decoder.current.y_overflow) {
                    decoder.queue.writeItem(.{
                        // PC mouse is using inverted Y
                        .rel_motion = .{ .dx = dx, .dy = -dy },
                    }) catch return error.Overrun;
                }
                decoder.state = .default;
            },
        }
    }

    pub fn pull(decoder: *MouseDecoder) ?MouseEvent {
        return decoder.queue.readItem();
    }

    const State = union(enum) {
        default,
        fetch_x,
        fetch_y: i9,
    };

    const MouseHeader = packed struct(u8) {
        left: bool,
        right: bool,
        middle: bool,
        always_set: bool = true,
        x_sign: bool,
        y_sign: bool,
        x_overflow: bool,
        y_overflow: bool,
    };
};

const KeyboardEvent = ashet.input.raw.KeyEvent;

const KeyboardDecoderSCS1 = struct {
    state: State = .default,
    queue: std.fifo.LinearFifo(KeyboardEvent, .{ .Static = 4 }) = .init(),

    pub fn drain(decoder: *KeyboardDecoderSCS1) void {
        while (decoder.pull()) |_| {}
    }

    pub fn pull(decoder: *KeyboardDecoderSCS1) ?KeyboardEvent {
        return decoder.queue.readItem();
    }

    pub fn push(decoder: *KeyboardDecoderSCS1, input: u8) error{Overrun}!void {
        switch (decoder.state) {
            .default => {
                if (input == 0xE0) {
                    decoder.state = .e0;
                } else if (input == 0xE1) {
                    decoder.state = .e1;
                } else {
                    const scancode = @as(u7, @truncate(input));
                    decoder.queue.writeItem(.{
                        .usage = @enumFromInt(scancode), // TODO: Implement PS/2 SCS1 this proper
                        .down = (scancode == input), // if different, the upper bit is set
                    }) catch return error.Overrun;
                }
            },

            .e0 => {
                defer decoder.state = .default;

                const scancode = @as(u7, @truncate(input));

                // Check for fake shifts and ignore them
                if (scancode == 0x2A or scancode == 0x36)
                    return;
                logger.debug("scs1 e0 code: 0x{X:0>2}", .{scancode});
                decoder.queue.writeItem(.{
                    .usage = @enumFromInt(@as(u8, 0x80) | scancode), // TODO: Implement PS/2 SCS1 this proper
                    .down = (scancode == input), // if different, the upper bit is set
                }) catch return error.Overrun;
            },

            .e1 => {
                decoder.state = .{ .e1_stage2 = input };
            },

            .e1_stage2 => |low| {
                const input7 = @as(u7, @truncate(input));
                const scancode = (@as(u16, input7) << 8) | low;

                logger.debug("scs1 e1 code: 0x{X:0>4}", .{scancode});
                decoder.queue.writeItem(.{
                    .usage = @enumFromInt(scancode), // TODO: Implement PS/2 SCS1 this proper
                    .down = (input7 == input), // if different, the upper bit is set
                }) catch return error.Overrun;
            },
        }
    }

    const State = union(enum) {
        default,
        e0,
        e1,
        e1_stage2: u8,
    };
};

const KeyboardDecoderSCS2 = struct {
    const scancode_map = ScanCodeMap.compile(
        @embedFile("../../data/keyboard/ps2/scs2"),
    );

    state: State = .default,
    queue: std.fifo.LinearFifo(KeyboardEvent, .{ .Static = 4 }) = .init(),
    release_event: bool = false,

    pub fn drain(decoder: *KeyboardDecoderSCS2) void {
        while (decoder.pull()) |_| {}
    }

    pub fn pull(decoder: *KeyboardDecoderSCS2) ?KeyboardEvent {
        return decoder.queue.readItem();
    }

    pub fn push(decoder: *KeyboardDecoderSCS2, input: u8) error{Overrun}!void {
        if (input == 0xF0) {
            decoder.release_event = true;
            return;
        }

        switch (decoder.state) {
            .default => {
                if (input == 0xE0) {
                    decoder.state = .e0;
                } else if (input == 0xE1) {
                    decoder.state = .e1;
                } else {
                    try decoder.process_key(input, .bare);
                }
            },

            .e0 => {
                defer decoder.state = .default;

                // Check for fake shifts and ignore them
                if (input == 0x12 or input == 0x59)
                    return;

                logger.debug("scs2 e0 code: 0x{X:0>2}", .{input});
                try decoder.process_key(input, .e0);
            },

            .e1 => {
                decoder.state = .{ .e1_stage2 = input };
            },

            .e1_stage2 => |low| {
                logger.debug("scs2 e1 code: 0x{X:0>2}{X:0>2}", .{ low, input });
                try decoder.process_key(input, .{ .e1 = low });
            },
        }
    }

    fn process_key(decoder: *KeyboardDecoderSCS2, raw: u8, tag: union(enum) { bare, e0, e1: u8 }) !void {
        defer {
            decoder.state = .default;
            decoder.release_event = false;
        }

        const maybe_usage = switch (tag) {
            .bare => scancode_map.get_bare(raw),
            .e0 => scancode_map.get_e0(raw),
            .e1 => |low| scancode_map.get_e1((@as(u16, low) << 8) | raw),
        };

        switch (tag) {
            .bare => logger.debug("SCS2 BARE: 0x{X:0>2} => {?}", .{ raw, maybe_usage }),
            .e0 => logger.debug("SCS2 E0:   0x{X:0>2} => {?}", .{ raw, maybe_usage }),
            .e1 => |second| logger.debug("SCS2 E1:   0x{X:0>2}{X:0>2} => {?}", .{ raw, second, maybe_usage }),
        }
        if (maybe_usage) |usage| {
            decoder.queue.writeItem(.{
                .usage = usage,
                .down = !decoder.release_event,
            }) catch return error.Overrun;
        }
    }

    const State = union(enum) {
        default,
        e0,
        e1,
        e1_stage2: u8,
    };
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

const ScanCodeMap = struct {
    const LUT = struct {
        scancode: u16,
        usage: KeyUsageCode,
    };

    /// Direct lookup for the base level scan codes
    bare: [256]?KeyUsageCode,

    /// Ordered look up table for E0 codes:
    e0: []const LUT,

    /// Ordered look up table for E1 codes:
    e1: []const LUT,

    pub fn get_bare(scm: *const ScanCodeMap, code: u8) ?KeyUsageCode {
        return scm.bare[code];
    }

    pub fn get_e0(scm: *const ScanCodeMap, code: u16) ?KeyUsageCode {
        const index = std.sort.binarySearch(LUT, scm.e0, code, compare);
        return if (index) |i|
            scm.e0[i].usage
        else
            null;
    }

    pub fn get_e1(scm: *const ScanCodeMap, code: u16) ?KeyUsageCode {
        const index = std.sort.binarySearch(LUT, scm.e1, code, compare);
        return if (index) |i|
            scm.e1[i].usage
        else
            null;
    }

    fn compare(where: u16, value: LUT) std.math.Order {
        if (where < value.scancode) return .lt;
        if (where > value.scancode) return .gt;
        return .eq;
    }

    pub fn compile(comptime source: []const u8) ScanCodeMap {
        @setEvalBranchQuota(50_000);
        var line_iter: ConfigFileIterator = .init(source);

        var bare: [256]?KeyUsageCode = @splat(null);
        var e0: []const LUT = &.{};
        var e1: []const LUT = &.{};

        while (line_iter.next()) |line| {
            const head = line.next().?;
            if (std.mem.eql(u8, head, "scancode")) {
                const key_str = line.next().?;
                const key = std.fmt.parseInt(u8, key_str, 16) catch @compileError("invalid hex: " ++ key_str);
                switch (key) {
                    0xE0, 0xE1 => {
                        const subkey_str = line.next().?;
                        const subkey = std.fmt.parseInt(u16, subkey_str, 16) catch @compileError("invalid hex: " ++ subkey_str);

                        const usage_str = line.next().?;
                        const usage = std.meta.stringToEnum(KeyUsageCode, usage_str) orelse @compileError("undefined usage: " ++ usage_str);

                        const lut: [1]LUT = .{.{
                            .scancode = subkey,
                            .usage = usage,
                        }};

                        switch (key) {
                            0xE0 => e0 = e0 ++ lut,
                            0xE1 => e1 = e1 ++ lut,
                            else => unreachable,
                        }
                    },
                    else => {
                        if (bare[key] != null) @compileError("duplicate key");
                        const usage_str = line.next().?;
                        const usage = std.meta.stringToEnum(KeyUsageCode, usage_str) orelse @compileError("undefined usage: " ++ usage_str);
                        bare[key] = usage;
                    },
                }
            }
        }

        return .{
            .bare = bare,
            .e0 = e0,
            .e1 = e1,
        };
    }
};
