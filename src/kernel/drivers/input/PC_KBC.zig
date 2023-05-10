const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.kbc);
const x86 = ashet.platforms.all.x86;

const PC_KBC = @This();
const Driver = ashet.drivers.Driver;
const CpuState = x86.idt.CpuState;

var global_channels = std.EnumSet(Channel){};
var global_devices = std.EnumArray(Channel, ?DeviceType).initFill(null);
var global_decoders = std.EnumArray(Channel, Decoder).initFill(undefined);

driver: Driver = .{
    .name = "Keyboard Controller",
    .class = .{
        .input = .{
            .pollFn = poll,
        },
    },
},

channels: *std.EnumSet(Channel) = &global_channels,
devices: *std.EnumArray(Channel, ?DeviceType) = &global_devices,
decoders: *std.EnumArray(Channel, Decoder) = &global_decoders,

/// This routine roughly follows the steps described in
/// https://wiki.osdev.org/%228042%22_PS/2_Controller#Initialising_the_PS.2F2_Controller
pub fn init() error{ Timeout, NoAcknowledge, SelfTestFailed, NoDevice, DoubleInitialize }!PC_KBC {
    if (global_channels.count() > 0) {
        return error.DoubleInitialize;
    }

    var kbc = PC_KBC{};

    x86.idt.set_IRQ_Handler(1, handleKeyboardInterrupt);
    x86.idt.set_IRQ_Handler(12, handleMouseInterrupt);

    // Step 3: Disable Devices
    // prevent the devices from sending data in the init sequence
    try kbc.writeCommand(.disable_primary_port);
    try kbc.writeCommand(.disable_secondary_port);

    // Step 4: Flush The Output Buffer
    // remove excess data from the buffers
    flushData();

    logger.debug("controller self test...", .{});
    flushData();

    // Step 5: Perform Controller Self Test
    {
        try kbc.writeCommand(.selftest);
        const response = try kbc.readData();
        if (response != 0x55)
            return error.SelfTestFailed;
    }

    // Step 6: Set the Controller Configuration Byte
    logger.debug("controller configuration...", .{});
    {
        try kbc.writeCommand(.read_cmd_byte);
        var cmd_byte = @bitCast(CommandByte, try kbc.readData());
        logger.debug("old config: {}", .{cmd_byte});
        cmd_byte.primary_irq_enabled = false;
        cmd_byte.secondary_irq_enabled = false;
        cmd_byte.scancode_translation_mode = false;
        logger.debug("new config: {}", .{cmd_byte});
        try kbc.writeCommand(.write_cmd_byte);
        try kbc.writeData(@bitCast(u8, cmd_byte));
    }

    logger.debug("test for secondary channel...", .{});
    flushData();

    // Step 7: Determine If There Are 2 Channels
    const has_secondary_channel = blk: {
        try kbc.writeCommand(.enable_secondary_port);

        try kbc.writeCommand(.read_cmd_byte);
        var cmd_byte = @bitCast(CommandByte, try kbc.readData());

        var two_channels = (cmd_byte.secondary_clk_enable == .enabled);

        try kbc.writeCommand(.disable_secondary_port);

        break :blk two_channels;
    };

    logger.debug("detect ports...", .{});
    flushData();

    // Step 8: Perform Interface Tests
    {
        try kbc.writeCommand(.test_primary_port);
        const primary_status = @intToEnum(PortTestResult, try kbc.readData());
        if (primary_status == .test_passed) {
            kbc.channels.insert(.primary);
        } else {
            logger.err("primary port test failed: {s}", .{@tagName(primary_status)});
        }

        if (has_secondary_channel) {
            try kbc.writeCommand(.test_secondary_port);
            const secondary_status = @intToEnum(PortTestResult, try kbc.readData());
            if (secondary_status == .test_passed) {
                kbc.channels.insert(.secondary);
            } else {
                logger.err("secondary port test failed: {s}", .{@tagName(secondary_status)});
            }
        }

        // no devices attached, abort mission
        if (kbc.channels.count() == 0)
            return error.NoDevice;
    }

    logger.debug("enable devices...", .{});
    flushData();

    // Step 9: Enable Devices
    {
        if (kbc.channels.contains(.primary)) {
            try kbc.writeCommand(.enable_primary_port);
        }
        if (kbc.channels.contains(.secondary)) {
            try kbc.writeCommand(.enable_secondary_port);
        }
    }

    logger.debug("reset devices...", .{});
    flushData();

    // Step 10: Reset Devices
    {
        var iter = kbc.channels.iterator();
        while (iter.next()) |chan| {
            try chan.writeCommand(DeviceMessage.common(.reset));
            if (chan.readData()) |response| {
                logger.debug("{s} reset response: 0x{X:0>2}", .{ @tagName(chan), response });
            } else |err| {
                logger.debug("{s} reset response: {!}", .{ @tagName(chan), err });
                kbc.channels.remove(chan);
            }
        }
    }

    // Step 11: Detect device types
    {
        var iter = kbc.channels.iterator();
        while (iter.next()) |chan| {
            logger.debug("detect {s} device type...", .{@tagName(chan)});
            flushData();

            const device_type = try chan.detectDeviceType();
            kbc.devices.set(chan, device_type);

            logger.info("{s} device identification: {?s}", .{ @tagName(chan), if (device_type) |dt| @tagName(dt) else null });
        }
    }

    // Step 12: Initialize devices and enable interrupts
    {
        var iter = kbc.channels.iterator();
        while (iter.next()) |chan| {
            if (kbc.devices.get(chan)) |device| {
                if (device.isKeyboard()) {
                    kbc.decoders.set(chan, Decoder{ .keyboard = .{} });
                    // TODO: Initialize keyboard

                    try chan.writeCommand(DeviceMessage.common(.set_defaults));

                    try chan.writeCommand(DeviceMessage.keyboard(.select_scancode_set));
                    try chan.writeData(0x01); // select scancode set 1

                    try chan.writeCommand(DeviceMessage.common(.enable_scanning));

                    x86.idt.enableIRQ(chan.irqNumber());
                } else if (device.isMouse()) {
                    kbc.decoders.set(chan, Decoder{ .mouse = .{} });

                    try chan.writeCommand(DeviceMessage.common(.set_defaults));
                    try chan.writeCommand(DeviceMessage.common(.enable_scanning));

                    flushData();
                    x86.idt.enableIRQ(chan.irqNumber());
                } else {
                    logger.err("unsupported device type {s}, removing device", .{@tagName(device)});
                    kbc.devices.set(chan, null);
                }
            }
        }
    }

    // Step 13: Enable IRQs in controller
    logger.debug("enable irq configuration...", .{});
    {
        try kbc.writeCommand(.read_cmd_byte);
        var cmd_byte = @bitCast(CommandByte, try kbc.readData());
        logger.debug("old config: {}", .{cmd_byte});
        cmd_byte.primary_irq_enabled = (kbc.devices.get(.primary) != null);
        cmd_byte.secondary_irq_enabled = (kbc.devices.get(.secondary) != null);
        logger.debug("new config: {}", .{cmd_byte});
        try kbc.writeCommand(.write_cmd_byte);
        try kbc.writeData(@bitCast(u8, cmd_byte));
    }

    return kbc;
}

const DeviceType = enum(u16) {
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

fn feedDataTo(chan: Channel) void {
    const device = global_devices.get(chan) orelse {
        logger.err("spurious data feed for unset device on {s} channel", .{@tagName(chan)});
        return;
    };

    const data = readRawData() catch {
        logger.err("failed to fetch data from KBC for channel {s}!", .{@tagName(chan)});

        // reset device decoder:
        if (device.isKeyboard()) {
            global_decoders.getPtr(chan).keyboard = .{};
        } else if (device.isMouse()) {
            global_decoders.getPtr(chan).mouse = .{};
        }

        return;
    };
    // logger.debug("{s}: 0x{X:0>2}", .{ @tagName(chan), data });

    if (device.isKeyboard()) {
        global_decoders.getPtr(chan).keyboard.feed(data);
    } else if (device.isMouse()) {
        global_decoders.getPtr(chan).mouse.feed(data);
    }
}

fn handleKeyboardInterrupt(state: *CpuState) *CpuState {
    feedDataTo(.primary);
    return state;
}

fn handleMouseInterrupt(state: *CpuState) *CpuState {
    feedDataTo(.secondary);
    return state;
}

fn poll(driver: *Driver) void {
    const kbc = @fieldParentPtr(PC_KBC, "driver", driver);
    kbc.internalPoll() catch |err| logger.err("error while polling kbc: {}", .{err});
}

fn internalPoll(kbc: *PC_KBC) !void {
    _ = kbc;
}

const Channel = enum {
    primary,
    secondary,

    pub fn irqNumber(chan: Channel) u4 {
        return switch (chan) {
            .primary => 1,
            .secondary => 12,
        };
    }

    pub fn readData(chan: Channel) !u8 {
        _ = chan;
        return try readRawData();
    }

    pub fn writeData(chan: Channel, data: u8) !void {
        if (chan == .secondary)
            try writeRawCommand(.write_secondary_port);
        logger.debug("write 0x{X:0>2} to {s} channel", .{ data, @tagName(chan) });
        try writeRawData(data);
    }

    pub fn writeCommand(chan: Channel, cmd: DeviceMessage) !void {
        try chan.writeData(cmd.data);
        while (true) {
            const response = try chan.readData();
            if (response == 0x00) {
                // buffer overrun
                continue;
            }
            if (response == ACK) {
                return;
            }

            logger.warn("Expected acknowledge (0x{X:0>2}), got 0x{X:0>2}", .{ ACK, response });
            return error.NoAcknowledge;
        }
    }

    pub fn detectDeviceType(chan: Channel) !?DeviceType {
        try chan.writeCommand(DeviceMessage.common(.disable_scanning));
        try chan.writeCommand(DeviceMessage.common(.identify));

        const lo = chan.readData() catch return null;
        const hi = chan.readData() catch 0x00;

        const device_id = @bitCast(u16, [2]u8{ lo, hi });

        return @intToEnum(DeviceType, device_id);
    }
};

fn channel(kbc: PC_KBC, chan: Channel) Channel {
    _ = kbc;
    return chan;
}

fn writeCommand(kbc: PC_KBC, cmd: Command) !void {
    _ = kbc;
    // logger.debug("writeCommand({})", .{cmd});
    try writeRawCommand(cmd);
}

fn writeData(kbc: PC_KBC, value: u8) !void {
    _ = kbc;
    // logger.debug("writeData({})", .{value});
    try writeRawData(value);
}

fn readData(kbc: PC_KBC) !u8 {
    _ = kbc;
    var result = readRawData();
    // logger.debug("readData() => {!X:0>2}", .{result});
    return try result;
}

fn busyLoop(cnt: u32) void {
    var i: u32 = 0;
    while (i < cnt) : (i += 1) {
        asm volatile (""
            :
            : [x] "r" (i),
        );
    }
}

fn delayPortRead() void {
    busyLoop(10_000);
}

fn writeRawData(data: u8) error{Timeout}!void {
    errdefer logger.err("timeout while executing writeRawData({})", .{data});
    var timeout: u8 = 255;
    while (readStatus().input_buffer == .full) {
        if (timeout == 0)
            return error.Timeout;
        timeout -= 1;
        delayPortRead();
    }
    x86.out(u8, ports.data, data);
}

fn readRawData() error{Timeout}!u8 {
    errdefer logger.err("timeout while executing readRawData()", .{});
    var timeout: u8 = 255;
    while (readStatus().output_buffer == .empty) {
        if (timeout == 0)
            return error.Timeout;
        timeout -= 1;
        delayPortRead();
    }
    return x86.in(u8, ports.data);
}

fn writeRawCommand(cmd: Command) error{Timeout}!void {
    errdefer logger.err("timeout while executing writeRawCommand({})", .{cmd});
    var timeout: u8 = 255;
    while (readStatus().input_buffer == .full) {
        if (timeout == 0)
            return error.Timeout;
        timeout -= 1;
        delayPortRead();
    }
    x86.out(u8, ports.command, @enumToInt(cmd));
}

fn readStatus() Status {
    return @bitCast(Status, x86.in(u8, ports.status));
}

fn flushData() void {
    while (readStatus().input_buffer == .full) {
        const item = x86.in(u8, ports.data);
        logger.debug("flush is discarding byte 0x{X:0>2}", .{item});
    }
}

const ports = struct {
    // Read port for output buffer, write port for input buffer
    const data = 0x60;

    /// Read from status port to get KBC status
    const status = 0x64;

    /// Write to command port to send KBC commands
    const command = 0x64;
};

const Status = packed struct(u8) {
    output_buffer: BufferState, // if full, data can be read from `data` port
    input_buffer: BufferState, // if empty, data can be written to `data` port
    selftest_ok: bool, // state of the self test. should always be `true`.
    last_port: u1, // last used port. 0=>0x60, 1=>0x61 or 0x64.
    keyboard_lock: KeyboardLockState,
    aux_input_buffer: BufferState, // PSAUX?
    timeout: bool, // If `true`, the device doesn't respond.
    parity_error: bool, // If `true`, a transmit error happend for the last read or write.
};

const KeyboardLockState = enum(u1) {
    locked = 0,
    unlocked = 1,
};

const BufferState = enum(u1) {
    empty = 0,
    full = 1,
};

const Command = enum(u8) {
    read_cmd_byte = 0x20,
    write_cmd_byte = 0x60,

    disable_secondary_port = 0xA7,
    enable_secondary_port = 0xA8,
    test_secondary_port = 0xA9, // 0x00 test passed, 0x01 clock line stuck low, 0x02 clock line stuck high, 0x03 data line stuck low, 0x04 data line stuck high

    selftest = 0xAA, // 0x55 test passed, 0xFC test failed

    test_primary_port = 0xAB, // 0x00 test passed, 0x01 clock line stuck low, 0x02 clock line stuck high, 0x03 data line stuck low, 0x04 data line stuck high

    diagnostic_dump = 0xAC,

    disable_primary_port = 0xAD,
    enable_primary_port = 0xAE,

    read_input_port = 0xC0,
    copy_lo_input_to_status = 0xC1, // Copy bits 0 to 3 of input port to status bits 4 to 7
    copy_hi_input_to_status = 0xC2, // Copy bits 4 to 7 of input port to status bits 4 to 7

    read_output_port = 0xD0,
    write_output_port = 0xD1, // Write next byte to Controller Output Port

    emulate_primary_input = 0xD2, // Write next byte to first PS/2 port output buffer (only if 2 PS/2 ports supported)
    emulate_secondary_input = 0xD3, // Write next byte to second PS/2 port output buffer (only if 2 PS/2 ports supported)

    write_secondary_port = 0xD4, // Write next byte to second PS/2 port input buffer (only if 2 PS/2 ports supported)
    _,
};

const CommandByte = packed struct(u8) {
    const ClockEnable = enum(u1) {
        enabled = 0,
        disabled = 1,
    };

    primary_irq_enabled: bool, // 0: First PS/2 port interrupt (1 = enabled, 0 = disabled)
    secondary_irq_enabled: bool, // 1: Second PS/2 port interrupt (1 = enabled, 0 = disabled, only if 2 PS/2 ports supported)
    system_flag: bool, // 2: System Flag (1 = system passed POST, 0 = your OS shouldn't be running)
    ignore_safety_state: bool, // 3: Should be zero
    primary_clk_enable: ClockEnable, // 4: First PS/2 port clock (1 = disabled, 0 = enabled)
    secondary_clk_enable: ClockEnable, // 5: Second PS/2 port clock (1 = disabled, 0 = enabled, only if 2 PS/2 ports supported)
    scancode_translation_mode: bool, // 6: First PS/2 port translation (1 = enabled, 0 = disabled)
    reserved: u1, // 7: must be zero

    pub fn format(self: CommandByte, comptime fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = opt;

        try writer.writeAll("CommandByte{ ");

        try writer.print("primary clk={s}, ", .{@tagName(self.primary_clk_enable)});
        try writer.print("primary irq={s}, ", .{if (self.primary_irq_enabled) "enabled" else "disabled"});

        try writer.print("secondary clk={s}, ", .{@tagName(self.secondary_clk_enable)});
        try writer.print("secondary irq={s}, ", .{if (self.secondary_irq_enabled) "enabled" else "disabled"});

        try writer.print("system state={s}, ", .{if (self.system_flag) "POST ok" else "POST failed"});
        try writer.print("scancode translation={s}", .{if (self.scancode_translation_mode) "on" else "off"});

        try writer.writeAll(" }");
    }
};

const DeviceMessage = extern union {
    data: u8,
    common: Common,
    keyboard: Keyboard,
    mouse: Mouse,

    pub fn data(value: u8) DeviceMessage {
        return .{ .data = value };
    }
    pub fn common(cmd: Common) DeviceMessage {
        return .{ .common = cmd };
    }
    pub fn keyboard(cmd: Keyboard) DeviceMessage {
        return .{ .keyboard = cmd };
    }
    pub fn mouse(cmd: Mouse) DeviceMessage {
        return .{ .mouse = cmd };
    }

    const Common = enum(u8) {
        identify = 0xF2,
        enable_scanning = 0xF4,
        disable_scanning = 0xF5,
        set_defaults = 0xF6,
        resend = 0xFE,
        reset = 0xFF,
    };

    const Keyboard = enum(u8) {
        set_leds = 0xED,
        selftest = 0xEE, // returns 0xEE
        select_scancode_set = 0xF0,
        set_repeat_rate = 0xF3,
        _,
    };

    const Mouse = enum(u8) {
        set_resolution = 0xE8,
        status_request = 0xE9,
        request_single_packet = 0xEB,
        get_mouse_id = 0xF2,
        set_sample_rate = 0xF3,
        _,
    };

    comptime {
        std.debug.assert(@sizeOf(@This()) == 1);
    }
};

const PortTestResult = enum(u8) {
    test_passed = 0x00,
    clock_line_stuck_low = 0x01,
    clock_line_stuck_high = 0x02,
    data_line_stuck_low = 0x03,
    data_line_stuck_high = 0x04,
    _,
};

const ACK = 0xFA;

const Decoder = union {
    mouse: MouseDecoder,
    keyboard: KeyboardDecoder,
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

    pub fn feed(decoder: *MouseDecoder, input: u8) void {
        switch (decoder.state) {
            .default => {
                const header = @bitCast(MouseHeader, input);
                if (header.always_set) {
                    decoder.state = .fetch_x;

                    if (header.left != decoder.current.left) {
                        ashet.input.pushRawEvent(.{
                            .mouse_button = .{ .button = .left, .down = header.left },
                        });
                    }
                    if (header.right != decoder.current.right) {
                        ashet.input.pushRawEvent(.{
                            .mouse_button = .{ .button = .right, .down = header.right },
                        });
                    }
                    if (header.middle != decoder.current.middle) {
                        ashet.input.pushRawEvent(.{
                            .mouse_button = .{ .button = .middle, .down = header.middle },
                        });
                    }
                    decoder.current = header;
                }
            },

            .fetch_x => {
                const dx = @bitCast(i8, input);
                decoder.state = .{ .fetch_y = dx };
            },

            .fetch_y => |dx| {
                const dy = @bitCast(i8, input);

                if ((dx != 0 or dy != 0) and !decoder.current.x_overflow and !decoder.current.y_overflow) {
                    ashet.input.pushRawEvent(.{
                        // PC mouse is using inverted Y
                        .mouse_motion = .{ .dx = dx, .dy = -dy },
                    });
                }

                decoder.state = .default;
            },
        }
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

const KeyboardDecoder = struct {
    state: State = .default,

    pub fn feed(decoder: *KeyboardDecoder, input: u8) void {
        switch (decoder.state) {
            .default => {
                if (input == 0xE0) {
                    decoder.state = .e0;
                } else if (input == 0xE1) {
                    decoder.state = .e1;
                } else {
                    const scancode = @truncate(u7, input);
                    ashet.input.pushRawEventFromIRQ(.{
                        .keyboard = .{
                            .scancode = scancode,
                            .down = (scancode == input), // if different, the upper bit is set
                        },
                    });
                }
            },

            .e0 => {
                defer decoder.state = .default;

                const scancode = @truncate(u7, input);

                // Check for fake shifts and ignore them
                if (scancode == 0x2A or scancode == 0x36)
                    return;
                std.log.debug("e0 code: 0x{X:0>2}", .{scancode});
                ashet.input.pushRawEventFromIRQ(.{
                    .keyboard = .{
                        .scancode = @as(u8, 0x80) | scancode,
                        .down = (scancode == input), // if different, the upper bit is set
                    },
                });
            },

            .e1 => {
                decoder.state = .{ .e1_stage2 = input };
            },

            .e1_stage2 => |low| {
                const input7 = @truncate(u7, input);
                const scancode = (@as(u16, input7) << 8) | low;

                std.log.debug("e1 code: 0x{X:0>4}", .{scancode});
                ashet.input.pushRawEventFromIRQ(.{
                    .keyboard = .{
                        .scancode = scancode,
                        .down = (input7 == input), // if different, the upper bit is set
                    },
                });
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
