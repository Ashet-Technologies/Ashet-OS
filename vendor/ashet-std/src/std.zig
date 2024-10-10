const std = @import("std");

pub const mpl = @import("mpl.zig");

const line_buffer = @import("line_buffer.zig");

pub const RingBuffer = @import("ringbuffer.zig").RingBuffer;
pub const HandleAllocator = @import("handle-allocator.zig").HandleAllocator;
pub const IndexPool = @import("indexpool.zig").IndexPool;
pub const FreeListAllocator = @import("mem/FreeListAllocator.zig").FreeListAllocator;
pub const StaticPool = @import("mem/StaticPool.zig").StaticPool;
pub const LineBuffer = line_buffer.LineBuffer;

test {
    _ = line_buffer;
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

/// Checks if `expected_node` is in the given linked list.
pub fn is_in_linked_list(comptime LinkedList: type, list: LinkedList, expected_node: *const LinkedList.Node) bool {
    var iter = list.first;
    while (iter) |node| : (iter = node.next) {
        if (node == expected_node)
            return true;
    }
    return false;
}
