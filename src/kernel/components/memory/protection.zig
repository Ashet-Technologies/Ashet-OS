//!
//! This module implements the generic memory protection related parts
//! of AshetOS.
//!
//! Memory protection allows setting memory ranges to read-only or read-write.
//!

const std = @import("std");
const log = std.log.scoped(.mprot);

const ashet = @import("../../main.zig");

const page_size = ashet.memory.page_size;
const machine_impl = ashet.machine.machine_config.memory_protection.?;

pub const Range = struct {
    base: usize,
    length: usize,

    pub fn from_slice(slice: anytype) Range {
        const bytes = std.mem.sliceAsBytes(slice);
        return .{
            .base = @intFromPtr(bytes.ptr),
            .length = bytes.len,
        };
    }
};

pub const Protection = enum {
    read_only,
    read_write,
};

pub fn initialize() !void {
    if (comptime !is_supported())
        return;

    log.info("initialize...", .{});
    try machine_impl.initialize();

    log.info("map kernel protected ranges...", .{});
    for (ashet.memory.get_protected_ranges()) |protected_range| {
        change(
            .{ .base = protected_range.base, .length = protected_range.length },
            protected_range.protection,
        );
    }

    log.info("activate...", .{});
    machine_impl.activate();

    log.info("memory protection ready.", .{});
}

pub fn is_supported() bool {
    return (ashet.machine.machine_config.memory_protection != null);
}

pub fn change(range: Range, protection: Protection) void {
    std.debug.assert(std.mem.isAligned(range.base, page_size));
    std.debug.assert(std.mem.isAligned(range.length, page_size));

    log.debug("Change 0x{X:0>8}+0x{X:0>8} to {s}", .{
        range.base, range.length, @tagName(protection),
    });

    machine_impl.update(range, protection);
}
