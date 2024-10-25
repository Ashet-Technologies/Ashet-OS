const std = @import("std");
const libashet = @import("ashet");

const ashet = @import("../main.zig");

pub const LoadedExecutable = struct {
    process_memory: []align(ashet.memory.page_size) u8,
    entry_point: usize,
};

pub const elf = @import("loader/elf.zig");
pub const ashex = @import("loader/ashex.zig");

pub const BinaryFormat = enum {
    elf,
    ashex,
};

pub fn load(
    file: *libashet.fs.File,
    allocator: std.mem.Allocator,
    format: BinaryFormat,
) !LoadedExecutable {
    return switch (format) {
        .elf => try elf.load(file, allocator),
        .ashex => try ashex.load(file, allocator),
    };
}
