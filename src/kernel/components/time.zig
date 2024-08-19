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

    pub fn ms_since_start(future: Instant) u64 {
        return @intFromEnum(future);
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
const Alarm = ashet.abi.datetime.Alarm;

var global_timer_queue: ashet.overlapped.WorkQueue = .{
    .wakeup_thread = null,
};

var global_alarm_queue: ashet.overlapped.WorkQueue = .{
    .wakeup_thread = null,
};

/// Period subsystem update, will finalize
/// all finished timers.
pub fn tick() void {
    process_timer_events();

    process_alarm_events();
}

fn process_alarm_events() void {
    const now = milliTimestamp();

    while (global_alarm_queue.get_head()) |next_alarm| {
        const alarm = next_alarm.arc.cast(Alarm).inputs;
        // the queue is sorted, so we've reached the end of what we can schedule right now
        if (now < @intFromEnum(alarm.when)) {
            break;
        }

        const dequeued, _ = global_alarm_queue.dequeue().?;
        std.debug.assert(dequeued == next_alarm);
        next_alarm.finalize(Alarm, .{});
    }
}

fn process_timer_events() void {
    const now = Instant.now();

    while (global_timer_queue.get_head()) |next_timer| {
        const timer = next_timer.arc.cast(Timer).inputs;
        // the queue is sorted, so we've reached the end of what we can schedule right now
        if (now.ms_since_start() < timer.timeout) {
            break;
        }

        const dequeued, _ = global_timer_queue.dequeue().?;
        std.debug.assert(dequeued == next_timer);
        next_timer.finalize(Timer, .{});
    }
}

const TimerComparer = struct {
    pub fn lt(_: @This(), lhs: *ashet.overlapped.AsyncCall, rhs: *ashet.overlapped.AsyncCall) bool {
        const lhs_timer = lhs.arc.cast(Timer);
        const rhs_timer = rhs.arc.cast(Timer);
        return lhs_timer.inputs.timeout < rhs_timer.inputs.timeout;
    }
};

pub fn schedule_timer(call: *ashet.overlapped.AsyncCall, inputs: Timer.Inputs) void {
    const now = Instant.now();
    if (now.ms_since_start() >= inputs.timeout) {
        call.finalize(Timer, .{});
    } else {
        global_timer_queue.priority_enqueue(call, null, TimerComparer{});
    }
}

const AlarmComparer = struct {
    pub fn lt(_: @This(), lhs: *ashet.overlapped.AsyncCall, rhs: *ashet.overlapped.AsyncCall) bool {
        const lhs_alarm = lhs.arc.cast(Alarm);
        const rhs_alarm = rhs.arc.cast(Alarm);
        return @intFromEnum(lhs_alarm.inputs.when) < @intFromEnum(rhs_alarm.inputs.when);
    }
};

pub fn schedule_alarm(call: *ashet.overlapped.AsyncCall, inputs: Alarm.Inputs) void {
    const now = milliTimestamp();
    if (now >= @intFromEnum(inputs.when)) {
        call.finalize(Alarm, .{});
    } else {
        global_alarm_queue.priority_enqueue(call, null, AlarmComparer{});
    }
}
