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
    system_start = 0,

    _,

    pub fn now() Instant {
        return @enumFromInt(ashet.machine_config.get_tick_count_ms());
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
        if (now.ms_since_start() < timer.timeout.ms_since_start()) {
            break;
        }

        const dequeued, _ = global_timer_queue.dequeue().?;
        std.debug.assert(dequeued == next_timer);
        next_timer.finalize(Timer, .{});
    }
}

fn cancel_timer(call: *ashet.overlapped.AsyncCall) void {
    std.debug.assert(global_timer_queue.remove(call));
}

fn cancel_alarm(call: *ashet.overlapped.AsyncCall) void {
    std.debug.assert(global_alarm_queue.remove(call));
}

pub fn schedule_timer(call: *ashet.overlapped.AsyncCall, inputs: Timer.Inputs) void {
    const now = Instant.now();
    if (now.ms_since_start() >= inputs.timeout.ms_since_start()) {
        call.finalize(Timer, .{});
    } else {
        call.cancel_fn = cancel_timer;
        global_timer_queue.priority_enqueue(call, null, TimerComparer{});
    }
}

pub fn schedule_alarm(call: *ashet.overlapped.AsyncCall, inputs: Alarm.Inputs) void {
    const now = milliTimestamp();
    if (now >= @intFromEnum(inputs.when)) {
        call.finalize(Alarm, .{});
    } else {
        call.cancel_fn = cancel_alarm;
        global_alarm_queue.priority_enqueue(call, null, AlarmComparer{});
    }
}

const TimerComparer = struct {
    pub fn lt(_: @This(), lhs: *ashet.overlapped.AsyncCall, rhs: *ashet.overlapped.AsyncCall) bool {
        const lhs_timer = lhs.arc.cast(Timer);
        const rhs_timer = rhs.arc.cast(Timer);
        return ashet.abi.Absolute.lt(lhs_timer.inputs.timeout, rhs_timer.inputs.timeout);
    }
};

const AlarmComparer = struct {
    pub fn lt(_: @This(), lhs: *ashet.overlapped.AsyncCall, rhs: *ashet.overlapped.AsyncCall) bool {
        const lhs_alarm = lhs.arc.cast(Alarm);
        const rhs_alarm = rhs.arc.cast(Alarm);
        return ashet.abi.DateTime.lt(lhs_alarm.inputs.when, rhs_alarm.inputs.when);
    }
};
