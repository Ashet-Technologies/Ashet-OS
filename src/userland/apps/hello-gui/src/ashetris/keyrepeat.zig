const ashet = @import("ashet");
const std = @import("std");
const types = @import("types.zig");

const KeyUsageCode = ashet.abi.KeyUsageCode;

const initial_delay = ashet.clock.Duration.from_ms(500);
const repeat_interval = ashet.clock.Duration.from_ms(75);

pub const KeyRepeat = struct {
    timer_iop: ashet.clock.Timer,
    next_timer_event: ?ashet.clock.Absolute,

    active_usage: ?KeyUsageCode,
    next_event_time: ?ashet.clock.Absolute,

    pub fn init() KeyRepeat {
        return KeyRepeat{
            .timer_iop = ashet.clock.Timer.init(ashet.clock.Absolute.system_start),
            .next_timer_event = null,
            .active_usage = null,
            .next_event_time = null,
        };
    }

    pub fn on_key_press(self: *KeyRepeat, usage: KeyUsageCode) void {
        self.next_event_time = ashet.clock.monotonic().increment_by(initial_delay);
        self.active_usage = usage;

        self.schedule_timer_event();
    }

    pub fn on_key_release(self: *KeyRepeat, usage: KeyUsageCode) void {
        if (self.active_usage == usage) {
            self.active_usage = null;
            self.next_event_time = null;
        }
    }

    pub fn on_timer_event(self: *KeyRepeat) ?KeyUsageCode {
        const this_timer_event = self.next_timer_event;
        self.next_timer_event = null;

        if (self.next_event_time != null and (this_timer_event == null or self.next_event_time.?.gt(this_timer_event.?))) {
            self.schedule_timer_event();
        } else if (self.active_usage != null) {
            self.next_event_time = ashet.clock.monotonic().increment_by(repeat_interval);
            self.schedule_timer_event();
            return self.active_usage.?;
        }
        return null;
    }

    fn schedule_timer_event(self: *KeyRepeat) void {
        if (self.next_timer_event == null) {
            self.next_timer_event = self.next_event_time;
            self.timer_iop.inputs.timeout = self.next_timer_event.?;
            ashet.overlapped.schedule(&self.timer_iop.arc) catch std.debug.panic("Failed to schedule key repeat timer", .{});
        }
    }
};
