const std = @import("std");

pub fn FixedPool(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();

        items: [size]T = undefined,
        maps: std.bit_set.StaticBitSet(size) = std.bit_set.StaticBitSet(size).initFull(),

        pub fn alloc(pool: *Self) ?*T {
            const index = pool.maps.findFirstSet() orelse return null;
            pool.maps.unset(index);
            return &pool.items[index];
        }

        pub fn get(pool: *Self, index: usize) *T {
            std.debug.assert(index < size);
            return &pool.items[index];
        }

        pub fn free(pool: *Self, item: *T) void {
            const index = @divExact((@intFromPtr(item) -% @intFromPtr(&pool.items[0])), @sizeOf(T));
            std.debug.assert(index < size);
            pool.maps.set(index);
        }
    };
}
