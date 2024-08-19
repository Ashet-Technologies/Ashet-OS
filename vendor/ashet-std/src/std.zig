const std = @import("std");

pub const mpl = @import("mpl.zig");

pub const RingBuffer = @import("ringbuffer.zig").RingBuffer;
pub const HandleAllocator = @import("handle-allocator.zig").HandleAllocator;
pub const IndexPool = @import("indexpool.zig").IndexPool;
pub const FreeListAllocator = @import("mem/FreeListAllocator.zig").FreeListAllocator;
pub const StaticPool = @import("mem/StaticPool.zig").StaticPool;

test {
    @import("std").testing.refAllDecls(@This());
}

pub fn mapToUnexpected(comptime E: type, err: anyerror) E {
    inline for (@typeInfo(E).ErrorSet.?) |err_desc| {
        if (err == @field(E, err_desc.name))
            return @field(E, err_desc.name);
    }
    std.log.warn("Unexpected error {s}. Mapping to error.Unexpected!", .{@errorName(err)});
    return error.Unexpected;
}
