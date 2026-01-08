const std = @import("std");
const astd = @import("ashet-std");

const ashet = @import("../../main.zig");

const logger = std.log.scoped(.ps2);

const ConfigFileIterator = ashet.utils.ConfigFileIterator;
const KeyUsageCode = ashet.abi.KeyUsageCode;

pub const KeyboardEvent = ashet.input.raw.Event;
pub const MouseEvent = ashet.input.raw.Event;

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

pub const MouseDecoder = struct {
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

    queue: astd.RingBuffer(MouseEvent, 4) = .{},

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
                        if (decoder.queue.full())
                            return error.Overrun;
                        decoder.queue.push(.{
                            .mouse_button = .{ .button = .left, .down = header.left },
                        });
                    }
                    if (header.right != decoder.current.right) {
                        if (decoder.queue.full())
                            return error.Overrun;
                        decoder.queue.push(.{
                            .mouse_button = .{ .button = .right, .down = header.right },
                        });
                    }
                    if (header.middle != decoder.current.middle) {
                        if (decoder.queue.full())
                            return error.Overrun;
                        decoder.queue.push(.{
                            .mouse_button = .{ .button = .middle, .down = header.middle },
                        });
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
                    if (decoder.queue.full())
                        return error.Overrun;
                    decoder.queue.push(.{
                        // PC mouse is using inverted Y
                        .mouse_rel_motion = .{ .dx = dx, .dy = -dy },
                    });
                }
                decoder.state = .default;
            },
        }
    }

    pub fn pull(decoder: *MouseDecoder) ?MouseEvent {
        return decoder.queue.pull();
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

pub const KeyboardDecoderSCS1 = struct {
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
                        .keyboard = .{
                            .usage = @enumFromInt(scancode), // TODO: Implement PS/2 SCS1 this proper
                            .down = (scancode == input), // if different, the upper bit is set
                        },
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
                    .keyboard = .{
                        .usage = @enumFromInt(@as(u8, 0x80) | scancode), // TODO: Implement PS/2 SCS1 this proper
                        .down = (scancode == input), // if different, the upper bit is set
                    },
                }) catch return error.Overrun;
            },

            .e1 => {
                decoder.state = .{ .e1_stage2 = input };
            },

            .e1_stage2 => |low| {
                defer decoder.state = .default;

                const input7 = @as(u7, @truncate(input));
                const scancode = (@as(u16, input7) << 8) | low;

                logger.debug("scs1 e1 code: 0x{X:0>4}", .{scancode});
                decoder.queue.writeItem(.{
                    .keyboard = .{
                        .usage = @enumFromInt(scancode), // TODO: Implement PS/2 SCS1 this proper
                        .down = (input7 == input), // if different, the upper bit is set
                    },
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

pub const KeyboardDecoderSCS2 = struct {
    pub const scancode_map = ScanCodeMap.compile(
        @embedFile("../../data/keyboard/ps2/scs2"),
    );

    state: State = .default,
    queue: astd.RingBuffer(KeyboardEvent, 4) = .{},
    release_event: bool = false,

    pub fn drain(decoder: *KeyboardDecoderSCS2) void {
        while (decoder.pull()) |_| {}
    }

    pub fn pull(decoder: *KeyboardDecoderSCS2) ?KeyboardEvent {
        return decoder.queue.pull();
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
            if (decoder.queue.full())
                return error.Overrun;
            decoder.queue.push(.{ .keyboard = .{
                .usage = usage,
                .down = !decoder.release_event,
            } });
        }
    }

    const State = union(enum) {
        default,
        e0,
        e1,
        e1_stage2: u8,
    };
};

pub const ScanCodeMap = struct {
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
