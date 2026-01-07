const std = @import("std");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.input);
const astd = @import("ashet-std");

const ConfigFileIterator = ashet.utils.ConfigFileIterator;

// We're doing a "dumb" alias to the ABI event here, it already contains the event type:
pub const Event = ashet.abi.InputEvent;

var shift_left_state: bool = false;
var shift_right_state: bool = false;

var ctrl_left_state: bool = false;
var ctrl_right_state: bool = false;

var alt_state: bool = false;
var alt_graph_state: bool = false;

var gui_left_state: bool = false;
var gui_right_state: bool = false;

pub fn initialize() void {
    //
}

/// Period subsystem update, will poll for input events
pub fn tick() void {
    var devices = ashet.drivers.enumerate(.input);
    while (devices.next()) |device| {
        device.poll();
    }

    {
        var cs = ashet.CriticalSection.enter();
        defer cs.leave();

        while (async_queue.pull()) |evt| {
            push_raw_event(evt);
        }
    }
}

pub const raw = struct {
    pub const Event = union(enum) {
        mouse_abs_motion: MouseAbsMotion,
        mouse_rel_motion: MouseRelMotion,
        mouse_button: MouseButton,
        keyboard: KeyEvent,
    };

    pub const MouseAbsMotion = struct {
        x: i16,
        y: i16,
    };

    pub const MouseRelMotion = struct {
        dx: i16,
        dy: i16,
    };

    pub const MouseButton = struct {
        button: ashet.abi.MouseButton,
        down: bool,
    };

    pub const KeyEvent = struct {
        usage: ashet.abi.KeyUsageCode,
        down: bool,
    };
};

/// stores incoming events from either interrupts or polling.
var event_queue: astd.RingBuffer(raw.Event, 32) = .{};

var event_awaiter: ?*ashet.overlapped.AsyncCall = null;

var async_queue: astd.RingBuffer(raw.Event, 16) = .{};

pub fn push_raw_event_from_irq(raw_event: raw.Event) void {
    var cs = ashet.CriticalSection.enter();
    defer cs.leave();

    if (async_queue.full()) {
        logger.warn("dropping {s} event", .{@tagName(async_queue.pull().?)});
    }
    async_queue.push(raw_event);
}

pub fn push_raw_event(raw_event: raw.Event) void {
    std.debug.assert(!ashet.platform.isInInterruptContext());

    logger.debug("push raw event {}", .{raw_event});

    if (event_queue.full()) {
        logger.warn("dropping {s} event", .{@tagName(event_queue.pull().?)});
    }

    // Push the raw event into the queue for processing and invoke
    // `getEvent()` so it can be converted into a "real" input event
    event_queue.push(raw_event);

    if (event_awaiter) |awaiter| {
        // This may *not* consume the pushed raw event, as not every raw input event
        // generates a user-visible event:
        if (getEvent()) |evt| {
            finish_arc(awaiter, evt);
            event_awaiter = null;
        }
    }
}

pub fn schedule_get_event(call: *ashet.overlapped.AsyncCall) void {
    // TODO: Implement this again!
    // const proc = call.thread.get_process();
    // if (!proc.isExclusiveVideoController()) {
    //     return call.finalize(ashet.abi.input.GetEvent, error.NonExclusiveAccess);
    // }

    if (event_awaiter != null) {
        return call.finalize(ashet.abi.input.GetEvent, error.InProgress);
    }

    if (getEvent()) |evt| {
        return finish_arc(call, evt);
    } else {
        call.cancel_fn = cancel_arc;
        event_awaiter = call;
    }
}

fn cancel_arc(call: *ashet.overlapped.AsyncCall) void {
    if (event_awaiter == call) {
        event_awaiter = null;
    }
}

fn finish_arc(call: *ashet.overlapped.AsyncCall, evt: Event) void {
    call.finalize(ashet.abi.input.GetEvent, .{ .event = evt });
}

fn convert_raw_event(raw_event: raw.Event) ?Event {
    return switch (raw_event) {
        .mouse_abs_motion => |data| Event{ .mouse = .{
            .event_type = .{ .input = .mouse_abs_motion },
            .dx = 0,
            .dy = 0,
            .x = data.x,
            .y = data.y,
            .button = .none,
        } },

        .mouse_rel_motion => |data| Event{ .mouse = .{
            .event_type = .{ .input = .mouse_rel_motion },
            .dx = data.dx,
            .dy = data.dy,
            .x = 0,
            .y = 0,
            .button = .none,
        } },

        .mouse_button => |data| {
            const button = switch (data.button) {
                .left => ashet.abi.MouseButton.left,
                .right => ashet.abi.MouseButton.right,
                .middle => ashet.abi.MouseButton.middle,
                .nav_previous => ashet.abi.MouseButton.nav_previous,
                .nav_next => ashet.abi.MouseButton.nav_next,
                .wheel_down => ashet.abi.MouseButton.wheel_down,
                .wheel_up => ashet.abi.MouseButton.wheel_up,
                else => return null,
            };

            const mouse_event: ashet.abi.MouseEvent = .{
                .event_type = .{ .input = if (data.down)
                    .mouse_button_press
                else
                    .mouse_button_release },
                .dx = 0,
                .dy = 0,
                .x = 0,
                .y = 0,
                .button = button,
            };

            return .{ .mouse = mouse_event };
        },

        .keyboard => |src_event| {
            const usage = src_event.usage;

            switch (usage) {
                .left_shift => shift_left_state = src_event.down,
                .right_shift => shift_right_state = src_event.down,
                .left_control => ctrl_left_state = src_event.down,
                .right_control => ctrl_right_state = src_event.down,
                .left_alt => alt_state = src_event.down,
                .right_alt => alt_graph_state = src_event.down,

                .left_gui => gui_left_state = src_event.down,
                .right_gui => gui_right_state = src_event.down,

                else => {},
            }

            const modifiers = getKeyboardModifiers();

            const text_ptr = keyboard.layout.translate(usage, modifiers.shift, modifiers.alt_graph);

            const event = ashet.abi.KeyboardEvent{
                .event_type = .{ .input = if (src_event.down)
                    .key_press
                else
                    .key_release },
                .usage = usage,
                .text_ptr = text_ptr,
                .text_len = if (text_ptr) |ptr| std.mem.len(ptr) else 0,
                .modifiers = modifiers,
                .pressed = src_event.down,
            };

            // We swallow the event if the global hotkey system consumes it
            if (ashet.global_hotkeys.handle(event))
                return null;

            return Event{ .keyboard = event };
        },
    };
}

pub fn getEvent() ?Event {
    while (true) {
        const raw_event = event_queue.pull() orelse return null;

        if (convert_raw_event(raw_event)) |event| {
            return event;
        }
    }
}

pub fn getKeyboardModifiers() ashet.abi.KeyboardModifiers {
    return ashet.abi.KeyboardModifiers{
        .shift = shift_left_state or shift_right_state,
        .alt = alt_state,
        .alt_graph = alt_graph_state,
        .ctrl = ctrl_left_state or ctrl_right_state,
        .gui = gui_left_state or gui_right_state,

        .shift_left = shift_left_state,
        .shift_right = shift_right_state,

        .ctrl_left = ctrl_left_state,
        .ctrl_right = ctrl_right_state,

        .gui_left = gui_left_state,
        .gui_right = gui_right_state,
    };
}

pub const keyboard = struct {
    pub const KeyUsage = ashet.abi.KeyUsageCode;

    pub var layout: *const Layout = &layouts.de;

    pub const layouts = struct {
        pub const de = Layout.compile(@embedFile("../data/keyboard/layouts/de"));
        pub const pl = Layout.compile(@embedFile("../data/keyboard/layouts/pl"));
    };

    pub const Layout = struct {
        const Strings = struct {
            normal: ?[*:0]const u8 = null,
            shift: ?[*:0]const u8 = null,
            alt_graph: ?[*:0]const u8 = null,
            shift_alt_graph: ?[*:0]const u8 = null,
        };

        const Map = blk: {
            @setEvalBranchQuota(10_000);
            break :blk std.enums.EnumArray(KeyUsage, Strings);
        };

        mapping: *const Map,

        pub fn compile(comptime source_def: []const u8) Layout {
            const mapping = comptime blk: {
                const Entry = struct {
                    keycode: KeyUsage,
                    strings: Strings = .{},
                };

                @setEvalBranchQuota(100_000);
                var lines = ConfigFileIterator.init(source_def);

                var mapping_list: []const Entry = &.{};

                while (lines.next()) |line| {
                    const head = line.next().?;

                    if (std.mem.eql(u8, head, "keymap")) {
                        const keycode_str = line.next() orelse @compileError("keymap requires a symbolic keycode: " ++ line.buffer);
                        const keycode = std.meta.stringToEnum(KeyUsage, keycode_str) orelse @compileError("keymap requires a valid keycode: " ++ keycode_str);

                        var entry = Entry{ .keycode = keycode };

                        entry.strings.normal = internAndMapOptionalString(line.next());
                        entry.strings.shift = internAndMapOptionalString(line.next());
                        entry.strings.alt_graph = internAndMapOptionalString(line.next());
                        entry.strings.shift_alt_graph = internAndMapOptionalString(line.next());

                        if (entry.strings.normal != null or entry.strings.shift != null or entry.strings.alt_graph != null or entry.strings.shift_alt_graph != null) {
                            mapping_list = mapping_list ++ [1]Entry{entry};
                        }
                    } else {
                        @compileError("Invalid line in keyboard layout definition: " ++ line.buffer);
                    }
                }

                var mapping = Map.initFill(Strings{});

                for (mapping_list) |item| {
                    if (mapping.get(item.keycode).normal != null)
                        @compileError(std.fmt.comptimePrint("Duplicate mapping for scancode {}!", .{item.scancode}));
                    mapping.set(item.keycode, item.strings);
                }

                break :blk mapping;
            };
            return Layout{
                .mapping = &mapping,
            };
        }

        fn internAndMapOptionalString(comptime str: ?[]const u8) ?[*:0]const u8 {
            return if (str) |s|
                internAndMapString(s)
            else
                null;
        }

        fn internAndMapString(comptime str: []const u8) [*:0]const u8 {
            const map = .{
                .LF = "\n",
                .CR = "\r",
                .TAB = "\t",
                .SPACE = " ",
                .NBSPACE = "\u{A0}",
            };

            inline for (std.meta.fields(@TypeOf(map))) |fld| {
                if (std.mem.eql(u8, str, "<" ++ fld.name ++ ">")) {
                    const name = @field(map, fld.name);
                    return internString(name.len, name.*);
                }
            }

            return internString(str.len, str[0..str.len].*);
        }

        fn internString(comptime len: comptime_int, comptime items: [len]u8) [*:0]const u8 {
            const storage: [len + 1]u8 = comptime items ++ [1]u8{0};
            return storage[0..len :0];
        }

        pub fn translate(self: Layout, key: KeyUsage, shift: bool, alt_graph: bool) ?[*:0]const u8 {
            const strings: Strings = self.mapping.get(key);

            if (shift and alt_graph and strings.shift_alt_graph != null)
                return strings.shift_alt_graph;

            if (alt_graph and strings.alt_graph != null)
                return strings.alt_graph;

            if (shift and strings.shift != null)
                return strings.shift;

            return strings.normal;
        }
    };
};
