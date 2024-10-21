//!
//! This file implements the Ashet OS kernel memory protection
//! on top of the Linux kernel mprotect syscall.
//!

const std = @import("std");
const ashet = @import("../../../main.zig");

const page_size = 4096;

pub const Range = ashet.memory.Range;

const Protection = ashet.memory.protection.Protection;
const AddressInfo = ashet.memory.protection.AddressInfo;

var mappings = std.AutoArrayHashMap(usize, AddressInfo).init(std.heap.page_allocator);
var enabled = false;

const PageSlice = struct {
    start: usize,
    end: usize,
};

pub fn initialize() !void {
    //
}

pub fn activate() void {
    enabled = true;

    var iter = mappings.iterator();
    while (iter.next()) |kv| {
        update_page(
            kv.key_ptr.*,
            kv.value_ptr.protection,
        );
    }
}

fn page_range(range: Range) PageSlice {
    const start = std.mem.alignBackward(usize, range.base, page_size);
    const end = std.mem.alignForward(usize, range.base + (range.length -| 1), page_size);
    return .{
        .start = @divExact(start, page_size),
        .end = @divExact(end, page_size),
    };
}

pub fn update(range: Range, protection: Protection) void {
    const prange = page_range(range);
    for (prange.start..prange.end) |page| {
        if (enabled) {
            update_page(page, protection);
        }
    }
}

fn update_page(page: usize, protection: Protection) void {
    const base = page_size * page;

    _ = std.posix.mprotect(
        @as([*]align(page_size) u8, @ptrFromInt(base))[0..page_size],
        switch (protection) {
            .forbidden => 0,
            .read_only => std.posix.PROT.READ | std.posix.PROT.EXEC,
            .read_write => std.posix.PROT.READ | std.posix.PROT.WRITE | std.posix.PROT.EXEC,
        },
    ) catch |err| std.debug.panic("failed to run mprotect: {}", .{err});

    const gop = mappings.getOrPut(page) catch @panic("failed to alloc kernel memory");
    if (gop.found_existing) {
        gop.value_ptr.* = .{
            .protection = protection,
            .was_accessed = false,
            .was_written = false,
        };
    }
    gop.value_ptr.protection = protection;
}

pub fn get_protection(address: usize) Protection {
    return query_address(address).protection;
}

pub fn query_address(address: usize) AddressInfo {
    const page = address / page_size;

    return mappings.get(page) orelse return .{
        .protection = .forbidden,
        .was_accessed = false,
        .was_written = false,
    };
}
