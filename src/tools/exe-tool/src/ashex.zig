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

    pub fn format(rtype: RelocationType, writer: *std.Io.Writer) !void {
        try writer.print("{s}{f}{f}{f}{f}{f}", .{
            @tagName(rtype.size),
            rtype.self.fmt('@'),
            rtype.addend.fmt('A'),
            rtype.base.fmt('B'),
            rtype.offset.fmt('O'),
            rtype.syscall.fmt('S'),
        });
    }

    pub fn fmtC(rtype: RelocationType, writer: *std.Io.Writer) !void {
        try writer.print("{s}{f}{f}{f}{f}{f}", .{
            switch (rtype.size) {
                .word8 => "u8",
                .word16 => "u16",
                .word32 => "u32",
                .word64 => "u64",
            },
            rtype.self.fmtAlways('@'),
            rtype.addend.fmtAlways('A'),
            rtype.base.fmtAlways('B'),
            rtype.offset.fmtAlways('O'),
            rtype.syscall.fmtAlways('S'),
        });
    }

    pub fn fmtNs(rtype: RelocationType, writer: *std.Io.Writer) !void {
        var written: bool = false;
        if (rtype.self != .unused) {
            if (written) try writer.writeAll(" ");
            try writer.print("{s}@", .{fld_to_str(rtype.self)});
            written = true;
        }
        if (rtype.addend != .unused) {
            if (written) try writer.writeAll(" ");
            try writer.print("{s}A", .{fld_to_str(rtype.addend)});
            written = true;
        }
        if (rtype.base != .unused) {
            if (written) try writer.writeAll(" ");
            try writer.print("{s}B", .{fld_to_str(rtype.base)});
            written = true;
        }
        if (rtype.offset != .unused) {
            if (written) try writer.writeAll(" ");
            try writer.print("{s}O", .{fld_to_str(rtype.offset)});
            written = true;
        }
        if (rtype.syscall != .unused) {
            if (written) try writer.writeAll(" ");
            try writer.print("{s}S", .{fld_to_str(rtype.syscall)});
            written = true;
        }
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

    fn fmt(rf: RelocationField, name: u7) RelFieldFmt {
        return .{ .rf = rf, .name = name };
    }
    fn fmtAlways(rf: RelocationField, name: u7) std.fmt.Alt(RelFieldFmt, RelFieldFmt.formatAlways) {
        return .{ .rf = rf, .name = name };
    }

    const RelFieldFmt = struct {
        rf: RelocationField,
        name: u7,

        pub fn format(self: RelFieldFmt, writer: *std.Io.Writer) !void {
            if (self.rf == .unused)
                return;
            try writer.print("{c}{c}", .{
                @as(u7, if (self.rf == .add) '+' else '-'),
                self.name,
            });
        }

        pub fn formatAlways(self: RelFieldFmt, writer: *std.Io.Writer) !void {
            if (self.rf == .unused) {
                try writer.writeAll("  ");
                return;
            }
            try writer.print("{c}{c}", .{
                @as(u7, if (self.rf == .add) '+' else '-'),
                self.name,
            });
        }
    };
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

    pub fn format(relocation: Relocation, writer: *std.Io.Writer) !void {
        try writer.print("Relocation(type={f}, addend={}, offset=0x{X:0>8}, syscall={})", .{
            relocation.type,
            relocation.addend,
            relocation.offset,
            relocation.syscall,
        });
    }
};

pub const PatchType = enum(u32) {
    patch_syscall = 0x01,

    _,
};
