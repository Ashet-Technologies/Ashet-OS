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
const Range = ashet.memory.Range;

pub const Protection = enum {
    /// Access to the memory isn't allowed and should panic
    forbidden,

    /// Access to the memory is read-only and writes should panic.
    read_only,

    /// Access to the memory is okay for both reads and writes.
    read_write,
};

var is_initialized = false;

pub fn initialize() !void {
    if (comptime !is_supported()) {
        log.warn("not available, skipping initialization...", .{});
        return;
    }

    log.info("initialize...", .{});
    try machine_impl.initialize();

    log.info("map kernel protected ranges...", .{});
    for (ashet.memory.get_protected_ranges()) |protected_range| {
        change(
            .{ .base = protected_range.base, .length = protected_range.length },
            protected_range.protection,
        );
    }

    log.info("enable page manager protection...", .{});
    ashet.memory.enable_page_manager_protection();

    log.info("activate...", .{});
    machine_impl.activate();

    log.info("memory protection ready.", .{});
    is_initialized = true;
}

pub fn is_supported() bool {
    return (ashet.machine.machine_config.memory_protection != null);
}

pub fn is_enabled() bool {
    return is_initialized;
}

pub fn get_protection(address: usize) Protection {
    if (comptime !is_supported())
        return .read_write;

    if (!is_enabled())
        return .read_write; // no protection means everything is read-write anyways

    return machine_impl.get_protection(address);
}

pub fn change(range: Range, protection: Protection) void {
    if (comptime !is_supported())
        return;

    std.debug.assert(std.mem.isAligned(range.base, page_size));
    std.debug.assert(std.mem.isAligned(range.length, page_size));

    log.debug("Change 0x{X:0>8}+0x{X:0>8} to {s}", .{
        range.base, range.length, @tagName(protection),
    });

    machine_impl.update(range, protection);
}
