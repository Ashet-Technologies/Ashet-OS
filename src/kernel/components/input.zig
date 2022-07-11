const std = @import("std");
const hal = @import("hal");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.input);

pub var cursor_x: u16 = 0;
pub var cursor_y: u16 = 0;

pub fn initialize() void {
    //
}

pub const Event = union(enum) {
    keyboard: ashet.abi.KeyboardEvent,
    mouse: ashet.abi.MouseEvent,
};

pub fn getEvent() ?Event {
    if (getKeyboardEvent()) |evt| {
        return Event{ .keyboard = evt };
    }
    if (getMouseEvent()) |evt| {
        return Event{ .mouse = evt };
    }
    return null;
}

pub fn getKeyboardEvent() ?ashet.abi.KeyboardEvent {
    const src_event = hal.input.getKeyboardEvent() orelse return null;

    return ashet.abi.KeyboardEvent{
        .scancode = src_event.key,
        .key = .unknown, // TODO: Perform key code translation here
        .pressed = src_event.down,
    };
}

pub fn getMouseEvent() ?ashet.abi.MouseEvent {
    const src_event = hal.input.getMouseEvent() orelse return null;

    switch (src_event) {
        .motion => |data| {
            const dx = @truncate(i16, std.math.clamp(data.dx, std.math.minInt(i16), std.math.maxInt(i16)));
            const dy = @truncate(i16, std.math.clamp(data.dy, std.math.minInt(i16), std.math.maxInt(i16)));

            cursor_x = @intCast(u16, std.math.clamp(@as(i32, cursor_x) + dx, 0, ashet.video.max_res_x - 1));
            cursor_y = @intCast(u16, std.math.clamp(@as(i32, cursor_y) + dy, 0, ashet.video.max_res_y - 1));

            return ashet.abi.MouseEvent{
                .type = .motion,
                .dx = dx,
                .dy = dy,
                .x = cursor_x,
                .y = cursor_y,
                .button = .none,
            };
        },
        .button => |data| {
            const event_type = if (data.down)
                ashet.abi.MouseEvent.Type.button_press
            else
                ashet.abi.MouseEvent.Type.button_release;
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
            return ashet.abi.MouseEvent{
                .type = event_type,
                .dx = 0,
                .dy = 0,
                .x = cursor_x,
                .y = cursor_y,
                .button = button,
            };
        },
    }
}
