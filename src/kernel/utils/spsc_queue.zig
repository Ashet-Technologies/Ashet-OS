const std = @import("std");

/// Single-producer, single-consumer queue that can be read or written
/// without sync issues from an interrupt.
pub fn SpScQueue(comptime T: type, comptime cap: usize) type {
    return struct {
        const Queue = @This();

        pub const element_type = T;
        pub const capacity = cap;

        pub const empty: Queue = .{};

        head: u32 = 0,
        tail: u32 = 0,
        items: [cap]T = undefined,

        pub inline fn is_empty(q: *const Queue) bool {
            const head = volatile_load(u32, &q.head);
            const tail = volatile_load(u32, &q.tail);
            return head == tail;
        }

        pub inline fn is_full(q: *const Queue) bool {
            const head = volatile_load(u32, &q.head);
            const tail = volatile_load(u32, &q.tail);
            return inc(head) == tail;
        }

        pub inline fn enqueue(q: *Queue, item: T) bool {
            const head = volatile_load(u32, &q.head);
            const next_head = inc(head);
            if (next_head == volatile_load(u32, &q.tail))
                return false;
            volatile_store(T, &q.items[head], item);
            volatile_store(u32, &q.head, next_head);
            return true;
        }

        pub inline fn dequeue(q: *Queue) ?T {
            const tail = volatile_load(u32, &q.tail);
            if (tail == volatile_load(u32, &q.head))
                return null;
            const value = volatile_load(T, &q.items[tail]);
            volatile_store(u32, &q.tail, inc(tail));
            return value;
        }

        inline fn inc(i: u32) u32 {
            return (i + 1) % cap;
        }
    };
}

inline fn volatile_load(comptime T: type, ptr: *const volatile T) T {
    return ptr.*;
}

inline fn volatile_store(comptime T: type, ptr: *volatile T, value: T) void {
    ptr.* = value;
}
