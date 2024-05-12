const std = @import("std");
const libashet = @import("ashet");

const ashet = @import("../main.zig");

pub const LoadedExecutable = struct {
    process_memory: []align(ashet.memory.page_size) u8,
    entry_point: usize,
};

pub const elf = @import("loader/elf.zig");

pub const BinaryFormat = enum {
    elf,
};

pub fn load(file: *libashet.fs.File, format: BinaryFormat) !LoadedExecutable {
    return switch (format) {
        .elf => try elf.load(file),
    };
}
