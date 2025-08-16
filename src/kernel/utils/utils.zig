const std = @import("std");

pub const mmio = @import("mmio.zig");
pub const fmt = @import("fmt.zig");

pub const SpinLock = @import("SpinLock.zig");

pub const FixedPool = @import("fixed_pool.zig").FixedPool;

pub const ansi = @import("ansi.zig");

pub inline fn volatile_read(comptime T: type, ptr: *const volatile T) T {
    return ptr.*;
}

pub inline fn volatile_write(comptime T: type, ptr: *volatile T, value: T) void {
    ptr.* = value;
}

/// Helper function to copy slice data into the typical syscall double-query pattern
/// which returns the actual length when no slice is given, and copies the given elements
/// when a slice is given.
pub fn copy_slice(comptime T: type, maybe_buf: ?[]T, source: []const T) usize {
    if (maybe_buf) |buf| {
        const len = @min(buf.len, source.len);
        @memcpy(buf[0..len], source[0..len]);
        return len;
    } else {
        return source.len;
    }
}
