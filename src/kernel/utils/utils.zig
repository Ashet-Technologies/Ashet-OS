const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../main.zig");
const ports = @import("../port/targets.zig");

pub const mmio = @import("mmio.zig");
pub const fmt = @import("fmt.zig");

pub const SpinLock = @import("SpinLock.zig");

pub const FixedPool = @import("fixed_pool.zig").FixedPool;

pub const ConfigFileIterator = @import("ConfigFileIterator.zig");

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

pub fn TargetPattern(comptime T: type) type {
    return struct {
        pub fn on_optimize(mode: std.builtin.OptimizeMode, value: T) @This() {
            return .{ .optimize = mode, .value = value };
        }

        pub fn on_platform(platform: ports.Platform, value: T) @This() {
            return .{ .platform = platform, .value = value };
        }

        pub fn on_machine(machine: ports.Machine, value: T) @This() {
            return .{ .machine = machine, .value = value };
        }

        optimize: ?std.builtin.OptimizeMode = null,
        platform: ?ports.Platform = null,
        machine: ?ports.Machine = null,

        value: T,
    };
}

/// Helper function that allows us selecting different values based on a basic
/// pattern matching
pub inline fn target_dependent_value(comptime T: type, default: T, comptime selectors: []const TargetPattern(T)) T {
    inline for (selectors) |pattern| {
        if (pattern.optimize != null and pattern.optimize != builtin.mode)
            continue;
        if (pattern.platform != null and pattern.platform != ashet.platform_id)
            continue;
        if (pattern.machine != null and pattern.machine != ashet.machine_id)
            continue;
        return pattern.value;
    }

    return default;
}
