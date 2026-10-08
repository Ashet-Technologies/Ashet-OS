//! Frame-pointer stack walking retained from Zig 0.15.2 (MIT).
//! Ashet uses the frame-pointer-only init path, without DWARF unwinding.
const std = @import("std");
const builtin = @import("builtin");
const MemoryAccessor = @import("stack_memory.zig");
const Self = @This();
first_address: ?usize,
fp: usize,
ma: MemoryAccessor = .init,

pub fn init(first_address: ?usize, fp: ?usize) Self {
    return .{ .first_address = first_address, .fp = fp orelse @frameAddress() };
}

pub fn deinit(self: *Self) void {
    self.ma.deinit();
}

pub fn next(self: *Self) ?usize {
    var address = self.nextInternal() orelse return null;
    if (self.first_address) |first| {
        while (address != first) address = self.nextInternal() orelse return null;
        self.first_address = null;
    }
    return address;
}

fn nextInternal(self: *Self) ?usize {
    if (builtin.omit_frame_pointer) return null;
    const offset = if (builtin.cpu.arch.isRISCV()) 2 * @sizeOf(usize) else 0;
    const fp = std.math.sub(usize, self.fp, offset) catch return null;
    if (fp == 0 or !std.mem.isAligned(fp, @alignOf(usize))) return null;
    const new_fp = self.ma.load(usize, fp) orelse return null;
    if (new_fp != 0 and new_fp < self.fp) return null;
    const new_pc = self.ma.load(usize, std.math.add(usize, fp, @sizeOf(usize)) catch return null) orelse return null;
    self.fp = new_fp;
    return new_pc;
}
