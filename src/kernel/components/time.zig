const std = @import("std");
const ashet = @import("../main.zig");

pub const tz = "Europe/Berlin";

pub const tz_offset = 1 * std.time.ns_per_hour;

pub fn nanoTimestamp() i128 {
    const rtc = ashet.drivers.first(.rtc) orelse @panic("no rtc driver found!");

    return rtc.nanoTimestamp() + tz_offset;
}

pub fn microTimestamp() i64 {
    return @as(i64, @intCast(@divTrunc(nanoTimestamp(), std.time.ns_per_us)));
}

pub fn milliTimestamp() i64 {
    return @as(i64, @intCast(@divTrunc(nanoTimestamp(), std.time.ns_per_ms)));
}

pub fn timestamp() i64 {
    return @divTrunc(milliTimestamp(), std.time.ms_per_s);
}

/// Monotonic clock in millisecond precision
pub const Instant = enum(u64) {
    _,

    pub fn now() Instant {
        return @enumFromInt(ashet.machine.get_tick_count());
    }

    pub fn ms_since(future: Instant, past: Instant) u64 {
        return @intFromEnum(future) - @intFromEnum(past);
    }

    pub fn add_ms(point: Instant, ms: u64) Instant {
        return @enumFromInt(@intFromEnum(point) + ms);
    }

    pub fn less_than(lhs: Instant, rhs: Instant) bool {
        return @intFromEnum(lhs) < @intFromEnum(rhs);
    }

    pub fn less_or_equal(lhs: Instant, rhs: Instant) bool {
        return (lhs == rhs) or lhs.less_than(rhs);
    }
};

/// Deadlines based on the monotonic clock.
pub const Deadline = struct {
    when: Instant,

    pub fn init_rel(timeout_ms: u32) Deadline {
        return .{ .when = Instant.now().add_ms(timeout_ms) };
    }

    pub fn init_abs(when: Instant) Deadline {
        return .{ .when = when };
    }

    pub fn is_reached(deadline: Deadline) bool {
        return deadline.when.less_or_equal(Instant.now());
    }

    pub fn move_forward(deadline: *Deadline, delta_ms: u32) void {
        deadline.when = deadline.when.add_ms(delta_ms);
    }

    pub fn wait(deadline: Deadline) void {
        while (!deadline.is_reached()) {
            //
        }
    }
};

const Timer = ashet.abi.clock.Timer;

var global_timer_queue: ?*Timer = null;

/// Period subsystem update, will finalize
/// all finished timers.
pub fn tick() void {
    const now = nanoTimestamp();

    while (global_timer_queue) |timer| {
        if (now >= timer.inputs.timeout) {
            // the timer has been timed out, so schedule the IOP and remove it from the queue
            global_timer_queue = if (timer.arc.next) |next|
                ashet.abi.ARC.cast(Timer, next)
            else
                null;

            timer.arc.next = null;
            ashet.@"async".finalize(&timer.arc);
        } else {
            // the queue is sorted, so we've reached the end of what we can schedule right now
            return;
        }
    }
}

pub fn scheduleTimer(timer: *Timer) void {
    timer.arc.next = null;

    const now = nanoTimestamp();
    if (now >= timer.inputs.timeout) {
        ashet.@"async".finalize(&timer.arc);
    } else {
        const insert = timer.inputs.timeout;
        if (global_timer_queue == null) {
            // start the queue
            global_timer_queue = timer;
        } else if (global_timer_queue.?.inputs.timeout > insert) {
            // we're head of the queue
            timer.arc.next = &global_timer_queue.?.arc;
            global_timer_queue = timer;
        } else {
            // we're not the head of the queue, insert somewhere further in the list
            var iter = global_timer_queue;
            while (iter) |old| {
                std.debug.assert(old.inputs.timeout <= insert);
                const next = ashet.abi.ARC.cast(Timer, old.arc.next orelse {
                    // there's no next, just append to the end
                    old.arc.next = &timer.arc;
                    return;
                });

                if (next.inputs.timeout > insert) {
                    // the next element will timeout after the current one, let's insert here

                    timer.arc.next = &next.arc;
                    old.arc.next = &timer.arc;
                } else {
                    // iterate further
                    iter = next;
                }
            }
            unreachable;
        }
    }
}
