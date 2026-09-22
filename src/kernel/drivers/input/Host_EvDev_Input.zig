const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../../main.zig");
const codes = @import("../../data/input-event-codes.zig");
const evdev = @import("evdev.zig");
const linux = std.os.linux;
const logger = std.log.scoped(.host_evdev_input);

const Host_EvDev_Input = @This();
const Driver = ashet.drivers.Driver;

// These are kernel longs, not libc's time_t (which is 64-bit on i386 musl).
const InputEvent = extern struct {
    seconds: usize,
    microseconds: usize,
    type: u16,
    code: u16,
    value: i32,
};

comptime {
    if (builtin.cpu.arch == .x86) {
        std.debug.assert(@sizeOf(InputEvent) == 16);
        std.debug.assert(@offsetOf(InputEvent, "type") == 8);
    }
}

const KeyState = [codes.KEY.CNT / 8]u8;
const get_version = linux.IOCTL.IOR('E', 0x01, i32);
const get_keys = linux.IOCTL.IOR('E', 0x18, KeyState);
const records_per_poll = 64;
const events_per_poll = 16;

// Restore modifiers before ordinary keys so initial/resynchronized key presses
// are translated with the correct modifiers by the input subsystem.
const modifiers = [_]u16{
    codes.KEY.LEFTSHIFT, codes.KEY.RIGHTSHIFT,
    codes.KEY.LEFTCTRL,  codes.KEY.RIGHTCTRL,
    codes.KEY.LEFTALT,   codes.KEY.RIGHTALT,
    codes.KEY.LEFTMETA,  codes.KEY.RIGHTMETA,
};

driver: Driver = .{
    .name = "Host EvDev Input",
    .class = .{ .input = .{ .pollFn = poll } },
},
fd: ?std.posix.fd_t,
events: [records_per_poll]InputEvent = undefined,
event_index: usize = 0,
event_count: usize = 0,
pressed: KeyState = @splat(0),
snapshot: KeyState = @splat(0),
sync_index: ?usize = null,
dropped: bool = false,
wheel: i32 = 0,

pub fn init(path: []const u8) !Host_EvDev_Input {
    const fd = try std.posix.open(path, .{
        .ACCMODE = .RDONLY,
        .NONBLOCK = true,
        .CLOEXEC = true,
    }, 0);
    errdefer std.posix.close(fd);

    var version: i32 = undefined;
    try query(fd, get_version, &version);

    var device: Host_EvDev_Input = .{ .fd = fd };
    try device.synchronize();
    return device;
}

fn query(fd: std.posix.fd_t, request: u32, result: anytype) !void {
    while (true) {
        switch (linux.E.init(linux.ioctl(fd, request, @intFromPtr(result)))) {
            .SUCCESS => return,
            .INTR => continue,
            .NOTTY => return error.NotEvdevDevice,
            .NODEV => return error.DeviceDisconnected,
            else => return error.DeviceIoError,
        }
    }
}

fn synchronize(device: *Host_EvDev_Input) !void {
    device.snapshot = @splat(0);
    try query(device.fd.?, get_keys, &device.snapshot);
    device.sync_index = 0;
}

fn isPressed(state: *const KeyState, code: u16) bool {
    return state[code / 8] & (@as(u8, 1) << @as(u3, @truncate(code))) != 0;
}

fn setPressed(state: *KeyState, code: u16, down: bool) void {
    const mask = @as(u8, 1) << @as(u3, @truncate(code));
    if (down) {
        state[code / 8] |= mask;
    } else {
        state[code / 8] &= ~mask;
    }
}

fn keyEvent(code: u16, down: bool) ?ashet.input.raw.Event {
    if (evdev.keyFromEvdev(code)) |usage| {
        return .{ .keyboard = .{ .usage = usage, .down = down } };
    }
    if (evdev.mouseFromEvdev(code)) |button| {
        return .{ .mouse_button = .{ .button = button, .down = down } };
    }
    return null;
}

fn disable(device: *Host_EvDev_Input, comptime message: []const u8, args: anytype) void {
    const fd = device.fd orelse return;
    logger.err("disabling evdev fd {}: " ++ message, .{fd} ++ args);
    std.posix.close(fd);
    device.fd = null;
    device.event_count = 0;
    device.event_index = 0;
    device.wheel = 0;
    // Reconcile to an empty snapshot to release everything we published.
    device.snapshot = @splat(0);
    device.sync_index = 0;
}

fn poll(driver: *Driver) void {
    const device: *Host_EvDev_Input = @fieldParentPtr("driver", driver);
    var records_left: usize = records_per_poll;
    var events_left: usize = events_per_poll;

    while (events_left > 0) {
        if (device.sync_index) |index| {
            if (index == modifiers.len + codes.KEY.CNT) {
                device.sync_index = null;
                continue;
            }
            device.sync_index = index + 1;
            const code: u16 = if (index < modifiers.len) modifiers[index] else @intCast(index - modifiers.len);
            const down = isPressed(&device.snapshot, code);
            if (down != isPressed(&device.pressed, code)) {
                if (keyEvent(code, down)) |event| {
                    setPressed(&device.pressed, code, down);
                    ashet.input.push_raw_event(event);
                    events_left -= 1;
                }
            }
            continue;
        }

        if (device.wheel != 0) {
            // Keep each synthetic click together, even across poll boundaries.
            if (events_left < 2) return;
            const button: ashet.abi.MouseButton = if (device.wheel > 0) .wheel_up else .wheel_down;
            ashet.input.push_raw_event(.{ .mouse_button = .{ .button = button, .down = true } });
            ashet.input.push_raw_event(.{ .mouse_button = .{ .button = button, .down = false } });
            device.wheel += if (device.wheel > 0) @as(i32, -1) else 1;
            events_left -= 2;
            continue;
        }

        const fd = device.fd orelse return;
        if (records_left == 0) return;

        if (device.event_index == device.event_count) {
            const buffer = std.mem.sliceAsBytes(device.events[0..records_left]);
            const result = linux.read(fd, buffer.ptr, buffer.len);
            switch (linux.E.init(result)) {
                .SUCCESS => {},
                .INTR => continue,
                .AGAIN => return,
                else => |err| {
                    device.disable("read failed: {s}", .{@tagName(err)});
                    continue;
                },
            }
            if (result == 0 or result % @sizeOf(InputEvent) != 0) {
                device.disable("invalid read length: {}", .{result});
                continue;
            }
            device.event_index = 0;
            device.event_count = result / @sizeOf(InputEvent);
        }

        const event = device.events[device.event_index];
        device.event_index += 1;
        records_left -= 1;

        if (device.dropped) {
            if (event.type == codes.EV.SYN and event.code == codes.SYN.REPORT) {
                device.dropped = false;
                device.synchronize() catch |err| {
                    device.disable("state query failed: {s}", .{@errorName(err)});
                };
            }
            continue;
        }

        switch (event.type) {
            codes.EV.SYN => {
                if (event.code == codes.SYN.DROPPED) {
                    device.dropped = true;
                }
            },
            codes.EV.KEY => {
                if (event.code >= codes.KEY.CNT or event.value < 0 or event.value > 2) continue;
                const raw = keyEvent(event.code, event.value != 0) orelse continue;
                if (raw == .mouse_button and event.value == 2) continue;
                setPressed(&device.pressed, event.code, event.value != 0);
                ashet.input.push_raw_event(raw);
                events_left -= 1;
            },
            codes.EV.REL => switch (event.code) {
                codes.REL.X, codes.REL.Y => {
                    if (event.value == 0) continue;
                    const delta: i16 = @intCast(std.math.clamp(event.value, std.math.minInt(i16), std.math.maxInt(i16)));
                    ashet.input.push_raw_event(.{ .mouse_rel_motion = .{
                        .dx = if (event.code == codes.REL.X) delta else 0,
                        .dy = if (event.code == codes.REL.Y) delta else 0,
                    } });
                    events_left -= 1;
                },
                codes.REL.WHEEL => device.wheel = event.value,
                else => {},
            },
            else => {},
        }
    }
}
