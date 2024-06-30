const std = @import("std");

pub fn IndexPool(comptime Index: type, comptime limit: Index) type {
    return struct {
        const Self = @This();
        const BitSet = std.bit_set.StaticBitSet(limit);

        data: BitSet = BitSet.initFull(),

        pub fn alloc(self: *Self) ?Index {
            const index = self.data.findFirstSet() orelse return null;
            self.data.unset(index);
            return index;
        }

        pub fn free(self: *Self, index: Index) void {
            std.debug.assert(self.alive(index));
            self.data.set(index);
        }

        pub fn alive(self: *Self, index: Index) bool {
            return !self.data.isSet(index);
        }
    };
}
