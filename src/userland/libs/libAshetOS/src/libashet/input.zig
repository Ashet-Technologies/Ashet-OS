const std = @import("std");

const ashet = @import("../libashet.zig");

const abi = ashet.abi;

pub const Event = union(abi.InputEvent.Type) {
    key_press: abi.KeyboardEvent,
    key_release: abi.KeyboardEvent,

    mouse_rel_motion: abi.MouseEvent,
    mouse_abs_motion: abi.MouseEvent,
    mouse_button_press: abi.MouseEvent,
    mouse_button_release: abi.MouseEvent,
};

pub fn await_event() !Event {
    const out = try ashet.overlapped.performOne(abi.input.GetEvent, .{});
    return switch (out.event.event_type) {
        inline .key_press,
        .key_release,
        => |evt| @unionInit(Event, @tagName(evt), out.event.keyboard),

        inline .mouse_abs_motion,
        .mouse_rel_motion,
        .mouse_button_press,
        .mouse_button_release,
        => |evt| @unionInit(Event, @tagName(evt), out.event.mouse),
    };
}
