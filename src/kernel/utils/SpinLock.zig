const std = @import("std");
pub const SpinLock = @This();

pub const init: SpinLock = .{ .state = .unlocked };

const State = enum(u32) {
    unlocked = 0,
    locked = 1,
};

state: State,

pub fn lock(self: *SpinLock) void {
    // Try to grab the lock; if busy, spin until we observe it as free, then try again.
    while (true) {
        if (@cmpxchgWeak(State, &self.state, .unlocked, .locked, .acquire, .monotonic) == null) {
            // acquired
            return;
        }
        // Busy-wait until we see it become 0 to avoid hammering the cache line.
        while (@atomicLoad(State, &self.state, .acquire) != .unlocked) {
            std.atomic.spinLoopHint();
        }
    }
}

pub fn tryLock(self: *SpinLock) bool {
    // Succeeds immediately if it was unlocked.
    return @cmpxchgWeak(State, &self.state, .unlocked, .locked, .acquire, .monotonic) == null;
}

pub fn unlock(self: *SpinLock) void {
    // Release so prior writes become visible before the lock opens.
    @atomicStore(State, &self.state, .unlocked, .release);
}
