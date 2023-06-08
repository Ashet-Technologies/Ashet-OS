const std = @import("std");

pub fn StaticPool(comptime T: type, comptime max_size: comptime_int) type {
    return struct {
        const Pool = @This();

        pub const capacity = max_size;

        allocation: std.bit_set.StaticBitSet(max_size) = std.bit_set.StaticBitSet(max_size).initFull(),
        storage: [max_size]T = undefined,

        pub fn create(pool: *Pool) error{OutOfMemory}!*T {
            const index = pool.allocation.toggleFirstSet() orelse return error.OutOfMemory;
            return &pool.storage[index];
        }

        pub fn destroy(pool: *Pool, item: *T) void {
            const offset = @ptrToInt(item) - @ptrToInt(&pool.storage);
            const index = @divExact(offset, @sizeOf(T));
            std.debug.assert(index < pool.storage.len);
            pool.storage[index] = undefined;
            pool.allocation.set(index);
        }
    };
}
