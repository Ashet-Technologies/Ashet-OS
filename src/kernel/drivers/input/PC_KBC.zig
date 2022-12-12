const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.@"virtio-input");
const x86 = ashet.platforms.all.x86;

const PC_KBC = @This();
const Driver = ashet.drivers.Driver;
const CpuState = x86.idt.CpuState;

driver: Driver = .{
    .name = "Keyboard Controller",
    .class = .{
        .input = .{
            .pollFn = poll,
        },
    },
},

last_mouse: MouseState = MouseState{
    .left = false,
    .right = false,
    .middle = false,
    .x_sign = false,
    .y_sign = false,
    .x_overflow = false,
    .y_overflow = false,
},

pub fn init() error{Timeout}!PC_KBC {
    var kbc = PC_KBC{};

    x86.idt.set_IRQ_Handler(1, handleKeyboardInterrupt);

    kbc.flushData();

    // try kbc.writeCommand(.read_cmd_byte);
    // var cmd_byte = @bitCast(CommandByte, try kbc.readData());
    // cmd_byte.primary_irq_enabled = true;
    // cmd_byte.secondary_irq_enabled = true;
    // cmd_byte.ibm_compat_mode = false;
    // cmd_byte.xlat_mode = false;
    // try kbc.writeCommand(.write_cmd_byte);

    // try kbc.writeCommand(.enable_keyboard);

    // try kbc.writeCommand(.enable_mouse);
    // try kbc.writeData(@bitCast(u8, cmd_byte));

    // try kbc.writeMouseCommand(.set_defaults);
    // try kbc.writeMouseCommand(.enable_send_data);

    // try kbc.writeKeyboardCommand(.set_defaults);
    try kbc.writeKeyboardCommand(.enable);

    x86.idt.enableIRQ(1);

    return kbc;
}

var key_decoder = KeyboardDecoder{};

fn handleKeyboardInterrupt(state: *CpuState) *CpuState {
    var kbc = PC_KBC{};

    const data = kbc.readData() catch {
        std.log.err("failed to fetch data from KBC!", .{});
        key_decoder = KeyboardDecoder{};
        return state;
    };

    if (key_decoder.feed(data)) |event| {
        ashet.input.pushRawEventFromIRQ(.{ .keyboard = event });
    }

    return state;
}

fn poll(driver: *Driver) void {
    const kbc = @fieldParentPtr(PC_KBC, "driver", driver);
    kbc.internalPoll() catch |err| logger.err("error while polling kbc: {}", .{err});
}

fn internalPoll(kbc: *PC_KBC) !void {
    while (kbc.status().input_buffer == .full) {
        logger.info("primary data: {!}", .{kbc.readData()});
    }

    while (kbc.status().aux_input_buffer == .full) {
        const mouse_data = @bitCast(MouseState, try kbc.readData());
        if (!mouse_data.always_set) {
            // whoopsies, confusion!
            continue;
        }

        const dx = @bitCast(i8, try kbc.readData());
        const dy = @bitCast(i8, try kbc.readData());

        if (mouse_data.left != kbc.last_mouse.left) {
            ashet.input.pushRawEvent(.{
                .mouse_button = .{ .button = .left, .down = mouse_data.left },
            });
        }
        if (mouse_data.right != kbc.last_mouse.right) {
            ashet.input.pushRawEvent(.{
                .mouse_button = .{ .button = .right, .down = mouse_data.right },
            });
        }
        if (mouse_data.middle != kbc.last_mouse.middle) {
            ashet.input.pushRawEvent(.{
                .mouse_button = .{ .button = .middle, .down = mouse_data.middle },
            });
        }

        kbc.last_mouse = mouse_data;

        if (!mouse_data.x_overflow and !mouse_data.y_overflow) {

            // mouse_button: MouseButton,

            if (dx != 0 or dy != 0) {
                ashet.input.pushRawEvent(.{
                    .mouse_motion = .{ .dx = dx, .dy = -dy }, // PC mouse is using inverted Y
                });
            }
        }
    }
}

fn writeToKeyboard(kbc: PC_KBC, data: u8) !void {
    try kbc.writeData(data);
}

fn writeKeyboardCommand(kbc: PC_KBC, cmd: KeyboardCommand) !void {
    try kbc.writeData(@enumToInt(cmd));
}

fn writeToMouse(kbc: PC_KBC, data: u8) !void {
    try kbc.writeCommand(.mouse_command);
    try kbc.writeData(data);
}

fn writeMouseCommand(kbc: PC_KBC, cmd: MouseCommand) !void {
    try kbc.writeCommand(.mouse_command);
    try kbc.writeData(@enumToInt(cmd));
    const response = try kbc.readData();
    if (response != MOUSE_ACK)
        return error.NoAcknowledge;
}

fn writeData(kbc: PC_KBC, data: u8) error{Timeout}!void {
    var timeout: u8 = 255;
    while (kbc.status().input_buffer == .full) {
        if (timeout == 0)
            return error.Timeout;
        timeout -= 1;
    }
    x86.out(u8, ports.data, data);
}

fn readData(kbc: PC_KBC) error{Timeout}!u8 {
    var timeout: u8 = 255;
    while (kbc.status().output_buffer == .empty) {
        if (timeout == 0)
            return error.Timeout;
        timeout -= 1;
    }
    return x86.in(u8, ports.data);
}

fn writeCommand(kbc: PC_KBC, cmd: Command) error{Timeout}!void {
    var timeout: u8 = 255;
    while (kbc.status().input_buffer == .full) {
        if (timeout == 0)
            return error.Timeout;
        timeout -= 1;
    }
    x86.out(u8, ports.command, @enumToInt(cmd));
}

fn status(kbc: PC_KBC) Status {
    _ = kbc;
    return @bitCast(Status, x86.in(u8, ports.status));
}

fn flushData(kbc: PC_KBC) void {
    while (kbc.status().input_buffer == .full) {
        _ = x86.in(u8, ports.data);
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
    selftest = 0xAA,
    test_keyboard = 0xAB,
    enable_mouse = 0xA8,
    disable_mouse = 0xA7,
    read_cmd_byte = 0x20,
    write_cmd_byte = 0x60,
    mouse_command = 0xD4,

    enable_keyboard = 0xAE,
    disable_keyboard = 0xAD,

    read_input_port = 0xC0,

    read_output_port = 0xD0,
    write_output_port = 0xD1,
    _,
};

const CommandByte = packed struct(u8) {
    primary_irq_enabled: bool, // 0 - Aktiviert die Aktivierung des IRQ1, wenn Tastaturdaten, wie Scancodes, im Buffer vorhanden sind (Bit1 bei 64h gesetzt)
    secondary_irq_enabled: bool, // 1 - Aktiviert die Aktivierung des IRQ12, wenn Mausdaten, wie das MouseDataPacket, im Buffer vorhanden sind (Bit5 bei 64h gesetzt)
    system_flag: bool, // 2 - System Flag
    ignore_safety_state: bool, // 3 - ignoriere Sicherheitsverschluss-Status
    disable_keyboard: bool, // 4 - deaktiviere Keyboard
    ibm_compat_mode: bool, // 5 - IBM PC Kompatibilitäts-Modus - 0 - use 11-bit codes, 1 - use 8086 codes
    xlat_mode: bool, // 6 - IBM PC Kompatibilitäts-Modus - Auch XLAT, konvertiert wie der Befehl, alle Scancodes zu Set 1, ansonsten werden Roh-Daten
    //     geliefert. -> dieses Bit muss gelöscht sein, bevor man die Scancode-Sets per F0h wechselt, denn sonst nur Kauderwelsch ensteht :)
    reserved: u1,
};

const MouseCommand = enum(u8) {
    enable_send_data = 0xF4, // Teile der Maus mit, dass sie Daten an die CPU senden soll
    disable_send_data = 0xF5, // Teile der Maus mit, dass sie keine Daten an die CPU senden soll
    set_defaults = 0xF6, // Setze Mauseinstellungen auf Standarteinstellungen zurück
    _,
};

const KeyboardCommand = enum(u8) {
    set_leds = 0xED,
    selftest = 0xEE, // returns 0xEE
    select_scancode_set = 0xF0,
    identify = 0xF2,
    set_repeat_rate = 0xF3,
    enable = 0xF4,
    disable = 0xF5,
    set_defaults = 0xF6,
    reset = 0xFF,
    _,
};

const MOUSE_ACK = 0xFA;

const MouseState = packed struct(u8) {
    left: bool,
    right: bool,
    middle: bool,
    always_set: bool = true,
    x_sign: bool,
    y_sign: bool,
    x_overflow: bool,
    y_overflow: bool,
};

const KeyboardDecoder = struct {
    state: State = .default,

    pub fn feed(decoder: *KeyboardDecoder, input: u8) ?ashet.input.raw.KeyEvent {
        switch (decoder.state) {
            .default => {
                if (input == 0xE0) {
                    decoder.state = .e0;
                } else if (input == 0xE1) {
                    decoder.state = .e1;
                } else {
                    const scancode = @truncate(u7, input);
                    return ashet.input.raw.KeyEvent{
                        .scancode = scancode,
                        .down = (scancode == input), // if different, the upper bit is set
                    };
                }
                return null;
            },

            .e0 => {
                defer decoder.state = .default;

                const scancode = @truncate(u7, input);

                // Check for fake shifts and ignore them
                if (scancode == 0x2A or scancode == 0x36)
                    return null;
                std.log.info("e0 code: 0x{X:0>2}", .{scancode});
                return ashet.input.raw.KeyEvent{
                    .scancode = @as(u8, 0x80) | scancode,
                    .down = (scancode == input), // if different, the upper bit is set
                };
            },

            .e1 => {
                decoder.state = .{ .e1_stage2 = input };
                return null;
            },

            .e1_stage2 => |low| {
                const input7 = @truncate(u7, input);
                const scancode = (@as(u16, input7) << 8) | low;

                std.log.info("e1 code: 0x{X:0>4}", .{scancode});
                return ashet.input.raw.KeyEvent{
                    .scancode = scancode,
                    .down = (input7 == input), // if different, the upper bit is set
                };
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
