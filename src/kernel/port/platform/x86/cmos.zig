const std = @import("std");
const x86 = @import("../x86.zig");

/// A non-memory-mapped register map.
/// Accessible via ports 0x70 and 0x71, use the utility
/// function `readRegister` to access the fields in this
/// struct.
pub const Registers = extern struct {
    seconds: BCD,
    alarm_second: BCD,
    minute: BCD,
    alarm_minute: BCD,
    hour: BCD,
    alarm_hour: BCD,
    day_of_week: BCD,
    day_of_month: BCD,
    month: BCD,
    year: BCD,
    status_reg_a: u8,
    status_reg_b: u8,
    status_reg_c: u8, // read-only
    status_reg_d: u8, // read-only
    post_diagnose: packed struct(u8) {
        timeout_read_adapter_id: bool,
        adapter_init_error: bool,
        clock_error: bool,
        drive_error: bool,
        memory_size_error: bool,
        config_error: bool,
        checksum_error: bool,
        powersupply_error: bool,
    },
    shutdown_status: u8, // TODO: replace with bitfields
    floppy_disk_drives: packed struct(u8) {
        fdd0: FddType,
        fdd1: FddType,
    },
    reserved0: u8,
    hard_disk_drives: packed struct(u8) {
        hdd0: HddType,
        hdd1: HddType,
    },
    reserved1: u8,
    device_byte: packed struct(u8) {
        has_floppies: bool,
        has_x87: bool,
        has_keyboard: bool,
        has_display: bool,
        display: enum(u2) {
            bios_display_adapter = 0b00,
            cga_40_col = 0b01,
            cga_80_col = 0b10,
            monochrome = 0b11,
        },
        floppy_count: enum(u2) {
            @"1" = 0b00,
            @"2" = 0b01,
            _,
        },
    },
    base_memory_size: u16 align(1),
    extended_memory_size: u16 align(1),
    hdd0_ext_byte: u8,
    hdd1_ext_byte: u8,
    reserved2: [19]u8,
    cmos_checksum_hi: u8,
    cmos_checksum_lo: u8,
    extended_memory: u16 align(1),
    century: BCD,
    reserved3: [13]u8,

    comptime {
        std.debug.assert(@sizeOf(Registers) == 0x40);
    }
};

pub const FddType = enum(u4) {
    none = 0b0000,
    @"5 1/4 SD" = 0b0001, //= 5 1/4 - 360 kB
    @"5 1/4 DD" = 0b0010, //= 5 1/4 - 1.2 MB
    @"3 1/2 SD" = 0b0011, //= 3 1/2 - 720 kB
    @"3 1/2 DD" = 0b0100, //= 3 1/2 - 1.44 MB
    _,
};

pub const HddType = enum(u4) {
    none = 0b0000,
    extended = 0b1111,
    _,
};

pub const BCD = packed struct(u8) {
    lo: u4,
    hi: u4,

    pub fn toInt(val: BCD) u8 {
        const hi = @as(u8, val.hi);
        const lo = @as(u8, val.lo);
        return 10 * hi + lo;
    }

    pub fn format(bcd: BCD, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{d}{d}", .{ bcd.hi, bcd.lo });
    }
};

pub const control_port = 0x70;
pub const data_port = 0x71;

const RegisterID = std.meta.FieldEnum(Registers);

pub fn readRegister(comptime reg: RegisterID, nmi_disabled: bool) std.meta.fieldInfo(Registers, reg).type {
    const reg_bit = @offsetOf(Registers, @tagName(reg)) | if (nmi_disabled) @as(u8, 0x80) else @as(u8, 0x00);
    x86.out(u8, control_port, reg_bit);
    return @as(std.meta.fieldInfo(Registers, reg).type, @bitCast(x86.in(u8, data_port)));
}
