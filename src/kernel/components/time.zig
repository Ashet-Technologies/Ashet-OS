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

pub fn get_tick_count() u64 {
    return ashet.machine.get_tick_count();
}

//

const Timer = ashet.abi.Timer;

var global_timer_queue: ?*Timer = null;

/// Period subsystem update, will finalize
/// all finished timers.
pub fn tick() void {
    const now = nanoTimestamp();

    while (global_timer_queue) |timer| {
        if (now >= timer.inputs.timeout) {
            // the timer has been timed out, so schedule the IOP and remove it from the queue
            global_timer_queue = if (timer.iop.next) |next|
                ashet.abi.IOP.cast(Timer, next)
            else
                null;

            timer.iop.next = null;
            ashet.io.finalize(&timer.iop);
        } else {
            // the queue is sorted, so we've reached the end of what we can schedule right now
            return;
        }
    }
}

pub fn scheduleTimer(timer: *Timer) void {
    timer.iop.next = null;

    const now = nanoTimestamp();
    if (now >= timer.inputs.timeout) {
        ashet.io.finalize(&timer.iop);
    } else {
        const insert = timer.inputs.timeout;
        if (global_timer_queue == null) {
            // start the queue
            global_timer_queue = timer;
        } else if (global_timer_queue.?.inputs.timeout > insert) {
            // we're head of the queue
            timer.iop.next = &global_timer_queue.?.iop;
            global_timer_queue = timer;
        } else {
            // we're not the head of the queue, insert somewhere further in the list
            var iter = global_timer_queue;
            while (iter) |old| {
                std.debug.assert(old.inputs.timeout <= insert);
                const next = ashet.abi.IOP.cast(Timer, old.iop.next orelse {
                    // there's no next, just append to the end
                    old.iop.next = &timer.iop;
                    return;
                });

                if (next.inputs.timeout > insert) {
                    // the next element will timeout after the current one, let's insert here

                    timer.iop.next = &next.iop;
                    old.iop.next = &timer.iop;
                } else {
                    // iterate further
                    iter = next;
                }
            }
            unreachable;
        }
    }
}
