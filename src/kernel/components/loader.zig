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
    // elf,
    ashex,
};

pub const LoadError = error{
    BadExecutable,
    SystemResources,
    DiskError,
};

pub fn load(
    file: *libashet.fs.File,
    allocator: std.mem.Allocator,
    format: BinaryFormat,
) LoadError!LoadedExecutable {
    return switch (format) {
        // TODO(0.15): .elf => return error.Unsupported,  try elf.load(file, allocator),
        .ashex => ashex.load(file, allocator) catch |err| switch (err) {
            error.SystemResources => error.SystemResources,
            error.DiskError => error.DiskError,

            error.AshexInvalidExecutable,
            error.AshexUnsupportedVersion,
            error.AshexMachineMismatch,
            error.AshexPlatformMismatch,
            error.AshexNoSectionData,
            error.AshexCorruptedFile,
            error.AshexInvalidRelocation,
            error.AshexUnsupportedSyscall,
            error.AshexInvalidSyscallIndex,
            => error.BadExecutable,
        },
    };
}
