const std = @import("std");

pub const Platform = enum(u8) {
    riscv32 = 0,
    arm32 = 1,
    x86 = 2,
};

pub const FileType = enum(u8) {
    machine32_le = 0,
};

pub const file_magic: [4]u8 = .{ 'A', 'S', 'H', 'X' };

pub const RelocationType = packed struct(u16) {
    size: RelocationSize,
    addend: RelocationField,
    base: RelocationField,
    offset: RelocationField,
    syscall: RelocationField,
    _padding: u6 = 0,
};

pub const RelocationSize = enum(u2) {
    word8 = 0,
    word16 = 1,
    word32 = 2,
    word64 = 3,
};

pub const RelocationField = enum(u2) {
    unused = 0b00,
    add = 0b10,
    subtract = 0b11,
};
