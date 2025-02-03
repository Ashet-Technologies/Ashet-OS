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

    fn fld_to_str(fld: RelocationField) []const u8 {
        return switch (fld) {
            .unused => "",
            .add => "+",
            .subtract => "-",
        };
    }

    pub fn format(rtype: RelocationType, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        var buffer: [128]u8 = undefined;

        const string = if (std.mem.eql(u8, fmt, "c"))
            try std.fmt.bufPrint(&buffer, "{s}{}{}{}{}{}", .{
                switch (rtype.size) {
                    .word8 => "u8",
                    .word16 => "u16",
                    .word32 => "u32",
                    .word64 => "u64",
                },
                std.fmt.Formatter(fmt_rel_field_always){ .data = .{ '@', rtype.self } },
                std.fmt.Formatter(fmt_rel_field_always){ .data = .{ 'A', rtype.addend } },
                std.fmt.Formatter(fmt_rel_field_always){ .data = .{ 'B', rtype.base } },
                std.fmt.Formatter(fmt_rel_field_always){ .data = .{ 'O', rtype.offset } },
                std.fmt.Formatter(fmt_rel_field_always){ .data = .{ 'S', rtype.syscall } },
            })
        else if (std.mem.eql(u8, fmt, "ns")) blk: {
            var stream = std.io.fixedBufferStream(&buffer);
            if (rtype.self != .unused) {
                if (stream.pos > 0)
                    try stream.writer().writeAll(" ");
                try stream.writer().print("{s}@", .{fld_to_str(rtype.self)});
            }
            if (rtype.addend != .unused) {
                if (stream.pos > 0)
                    try stream.writer().writeAll(" ");
                try stream.writer().print("{s}A", .{fld_to_str(rtype.addend)});
            }
            if (rtype.base != .unused) {
                if (stream.pos > 0)
                    try stream.writer().writeAll(" ");
                try stream.writer().print("{s}B", .{fld_to_str(rtype.base)});
            }
            if (rtype.offset != .unused) {
                if (stream.pos > 0)
                    try stream.writer().writeAll(" ");
                try stream.writer().print("{s}O", .{fld_to_str(rtype.offset)});
            }
            if (rtype.syscall != .unused) {
                if (stream.pos > 0)
                    try stream.writer().writeAll(" ");
                try stream.writer().print("{s}S", .{fld_to_str(rtype.syscall)});
            }
            break :blk stream.getWritten();
        } else try std.fmt.bufPrint(&buffer, "{s}{}{}{}{}{}", .{
            @tagName(rtype.size),
            std.fmt.Formatter(fmt_rel_field){ .data = .{ '@', rtype.self } },
            std.fmt.Formatter(fmt_rel_field){ .data = .{ 'A', rtype.addend } },
            std.fmt.Formatter(fmt_rel_field){ .data = .{ 'B', rtype.base } },
            std.fmt.Formatter(fmt_rel_field){ .data = .{ 'O', rtype.offset } },
            std.fmt.Formatter(fmt_rel_field){ .data = .{ 'S', rtype.syscall } },
        });

        try std.fmt.formatBuf(string, options, writer);
    }
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
        try writer.print("Relocation(type={}, addend={}, offset=0x{X:0>8}, syscall={})", .{
            relocation.type,
            relocation.addend,
            relocation.offset,
            relocation.syscall,
        });
    }
};

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

fn fmt_rel_field_always(val: struct { u7, RelocationField }, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    if (val[1] == .unused) {
        try writer.writeAll("  ");
        return;
    }
    _ = fmt;
    _ = options;
    try writer.print("{c}{c}", .{
        @as(u7, if (val[1] == .add) '+' else '-'),
        val[0],
    });
}

pub const PatchType = enum(u32) {
    patch_syscall = 0x01,

    _,
};
