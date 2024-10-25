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
    self: RelocationField,
    addend: RelocationField,
    base: RelocationField,
    offset: RelocationField,
    syscall: RelocationField,
    _padding: u4 = 0,
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

pub const Header = struct {
    icon_size: u32,
    icon_offset: u32,

    vmem_size: u32,
    entry_point: u32,

    syscall_offset: u32,
    syscall_count: u32,

    load_header_offset: u32,
    load_header_count: u32,

    bss_header_offset: u32,
    bss_header_count: u32,

    relocation_offset: u32,
    relocation_count: u32,
};

pub const Relocation = struct {
    type: RelocationType,
    syscall: u16,
    offset: u32,
    addend: i32,

    pub fn format(relocation: Relocation, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Relocation(type={s}{}{}{}{}{}, addend={}, offset=0x{X:0>8}, syscall={})", .{
            @tagName(relocation.type.size),
            std.fmt.Formatter(fmt_rel_field){ .data = .{ '@', relocation.type.self } },
            std.fmt.Formatter(fmt_rel_field){ .data = .{ 'A', relocation.type.addend } },
            std.fmt.Formatter(fmt_rel_field){ .data = .{ 'B', relocation.type.base } },
            std.fmt.Formatter(fmt_rel_field){ .data = .{ 'O', relocation.type.offset } },
            std.fmt.Formatter(fmt_rel_field){ .data = .{ 'S', relocation.type.syscall } },
            relocation.addend,
            relocation.offset,
            relocation.syscall,
        });
    }

    fn fmt_rel_field(val: struct { u7, RelocationField }, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        if (val[1] == .unused)
            return;
        _ = fmt;
        _ = options;
        try writer.print("{c}{c}", .{
            @as(u7, if (val[1] == .add) '+' else '-'),
            val[0],
        });
    }
};
