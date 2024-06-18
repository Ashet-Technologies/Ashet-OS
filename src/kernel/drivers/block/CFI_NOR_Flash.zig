//!
//! Common Flash Memory Interface
//! https://web.archive.org/web/20110716114706/http://www.spansion.com/Support/AppNotes/cfi_100_20011201.pdf
//!
const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.@"cfi-nor-flash");

const CFI_NOR_Flash = @This();
const Driver = ashet.drivers.Driver;

driver: Driver,
offset: usize,
byte_size: usize,

pub fn init(offset: usize, length: usize) error{InvalidDevice}!CFI_NOR_Flash {
    inline for ([_]type{ u8, u16, u32 }) |T| {
        const flash_mem = @as([*]volatile T, @ptrFromInt(offset));

        flash_mem[0x55] = 0x98; // enter CFI interface
        const seq = [3]u8{
            @as(u8, @truncate(flash_mem[0x10])),
            @as(u8, @truncate(flash_mem[0x11])),
            @as(u8, @truncate(flash_mem[0x12])),
        };
        flash_mem[0x55] = 0xFF; // return to read array mode

        if (std.mem.eql(u8, &seq, "QRY")) {
            try CfiDeviceImpl(T).init(flash_mem);

            return CFI_NOR_Flash{
                .driver = .{
                    .name = std.fmt.comptimePrint("CFI NOR Flash ({} bit)", .{@bitSizeOf(T)}),
                    .class = .{
                        .block = .{
                            .name = "PF0",
                            .block_size = 512,
                            .num_blocks = length / 512,
                            .presentFn = CfiDeviceImpl(T).present,
                            .readFn = CfiDeviceImpl(T).read,
                            .writeFn = CfiDeviceImpl(T).write,
                        },
                    },
                },
                .offset = offset,
                .byte_size = length,
            };
        }
    }
    return error.InvalidDevice;
}

const FmtCursedVoltage = struct {
    value: u8,

    pub fn format(volts: FmtCursedVoltage, fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = opt;

        if (volts.value == 0) {
            try writer.writeAll("-");
        } else {
            const lower: u4 = @truncate(volts.value >> 0); // BCD
            const upper: u4 = @truncate(volts.value >> 4); // HEX

            try writer.print("{}.{}V", .{ upper, lower });
        }
    }
};

/// Formats a voltage from the CFI interface.
/// low nibble is the tenths digit, bcd encoded
/// high nibble is the voltage, integer encoded
fn fmtCursedVoltage(value: u8) FmtCursedVoltage {
    return FmtCursedVoltage{ .value = value };
}

pub fn CfiDeviceImpl(comptime InterfaceWidth: type) type {
    return struct {
        fn init(base: [*]volatile InterfaceWidth) error{}!void {
            enterMode(base, .cfi_query);
            defer enterMode(base, .array_read);

            // TODO: Query all information

            const vendor = readRegister(base, u16, regs.vendor);
            const extended_query = readRegister(base, u16, regs.extended_query);

            logger.info("vendor                  = 0x{X:0>4}", .{vendor});
            logger.info("extended_query          = 0x{X:0>4}", .{extended_query});
            logger.info("alt_vendor              = 0x{X:0>4}", .{readRegister(base, u16, regs.alt_vendor)});
            logger.info("alt_extended_query      = 0x{X:0>4}", .{readRegister(base, u16, regs.alt_extended_query)});
            logger.info("vcc_lower_voltage       = {}", .{fmtCursedVoltage(readRegister(base, u8, regs.vcc_lower_voltage))});
            logger.info("vcc_upper_voltage       = {}", .{fmtCursedVoltage(readRegister(base, u8, regs.vcc_upper_voltage))});
            logger.info("vpp_lower_voltage       = {}", .{fmtCursedVoltage(readRegister(base, u8, regs.vpp_lower_voltage))});
            logger.info("vpp_upper_voltage       = {}", .{fmtCursedVoltage(readRegister(base, u8, regs.vpp_upper_voltage))});
            logger.info("device_density          = 2^{d}", .{readRegister(base, u8, regs.device_density)});
            logger.info("bus_interface           = 0x{X:0>4}", .{readRegister(base, u16, regs.bus_interface)});
            logger.info("multi_byte_write_size   = 2^{d}", .{readRegister(base, u16, regs.multi_byte_write_size)});

            const regions = readRegister(base, u8, regs.num_erase_block_regions);
            logger.info("num_erase_block_regions = {d}", .{regions});
            for (@as([*]void, undefined)[0..regions], 0..) |_, i| {
                logger.info("  region[{}].block count = {d}", .{ i, translateBlockRegionBlockCount(readRegister(base, u16, regs.blockRegionNumBlocks(@as(u16, @truncate(i))))) });
                // TODO: logger.info("  region[{}].block_size  = {d}", .{ i, std.fmt.fmtIntSizeBin(translateBlockRegionBlockSize(readRegister(base, u16, regs.blockRegionBlockSize(@truncate(u16, i))))) });
                logger.info("  region[{}].block_size  = {d}", .{ i, translateBlockRegionBlockSize(readRegister(base, u16, regs.blockRegionBlockSize(@as(u16, @truncate(i))))) });
            }

            if (extended_query != 0) {
                logger.info("ext query                = {c}{c}{c}", .{
                    readRegister(base, u8, extended_query + 0),
                    readRegister(base, u8, extended_query + 1),
                    readRegister(base, u8, extended_query + 2),
                });
                logger.info("version                  = {c}.{c}", .{
                    readRegister(base, u8, extended_query + 3),
                    readRegister(base, u8, extended_query + 4),
                });
            }
        }

        pub fn enterMode(base: [*]volatile InterfaceWidth, mode: Mode) void {
            base[0x55] = @intFromEnum(mode);
        }

        pub fn readRegister(base: [*]volatile InterfaceWidth, comptime T: type, reg: u16) T {
            var bytes: [@sizeOf(T)]u8 = undefined;
            for (&bytes, 0..) |*b, i| {
                b.* = @as(u8, @truncate(base[reg + i]));
            }
            return std.mem.readIntLittle(T, &bytes);
        }

        fn present(driver: *Driver) bool {
            const device: *CFI_NOR_Flash = @fieldParentPtr("driver", driver);
            const base = @as([*]volatile InterfaceWidth, @ptrFromInt(device.offset));
            _ = base;
            return true;
        }

        fn read(driver: *Driver, block: u64, data: []u8) ashet.storage.BlockDevice.ReadError!void {
            const device: *CFI_NOR_Flash = @fieldParentPtr("driver", driver);
            const base = @as([*]volatile InterfaceWidth, @ptrFromInt(device.offset));

            const block_items = device.driver.class.block.block_size / @sizeOf(InterfaceWidth);
            const block_start = std.math.cast(usize, block_items * block) orelse return error.InvalidBlock;

            enterMode(base, .array_read);
            for (std.mem.bytesAsSlice(InterfaceWidth, data), base[block_start .. block_start + block_items]) |*dest, src| {
                dest.* = src;
            }
        }

        fn write(driver: *Driver, block: u64, data: []const u8) ashet.storage.BlockDevice.WriteError!void {
            const device: *CFI_NOR_Flash = @fieldParentPtr("driver", driver);
            const base = @as([*]volatile InterfaceWidth, @ptrFromInt(device.offset));

            // we cannot write 256 byte blocks on 8 bit address bus
            if (@sizeOf(InterfaceWidth) == 1)
                return error.NotSupported;

            const block_items = std.math.cast(InterfaceWidth, device.driver.class.block.block_size / @sizeOf(InterfaceWidth)) orelse return error.NotSupported;
            const block_start = std.math.cast(InterfaceWidth, block_items * block) orelse return error.InvalidBlock;
            const block_end = block_start + block_items;

            // WARNING: THIS IS ONLY VALID FOR THE QEMU PFLASH1!
            // Reference: ${QEMU_SRC}/hw/block/pflash_cfi01.c

            enterMode(base, .write_to_buffer); // 0xE8
            defer enterMode(base, .array_read);

            const prog_error = 0x10;

            if ((base[0x55] & prog_error) != 0)
                return error.Fault;

            base[0x55] = block_items; // write block size in interface width

            if ((base[0x55] & prog_error) != 0)
                return error.Fault;

            for (base[block_start..block_end], std.mem.bytesAsSlice(InterfaceWidth, data)) |*dest, src| {
                dest.* = src;
            }

            if ((base[0x55] & prog_error) != 0)
                return error.Fault;

            base[0x55] = 0xD0; // confirm

            if ((base[0x55] & prog_error) != 0)
                return error.Fault;
        }
    };
}

pub const Mode = enum(u8) {
    cfi_query = 0x98,
    array_read = 0xFF,

    // qemu+intel mode
    single_byte_program = 0x10,
    single_byte_program_alt = 0x40,
    block_erase = 0x20,
    clear_status_bits = 0x50,
    status_register = 0x70,
    read_device_id = 0x90,
    write_to_buffer = 0xe8,
    probe_for_amd_flash = 0xf0,
};

const regs = struct {
    pub const query = 0x10; // 3 byte, "QRY"
    pub const vendor = 0x13; // 2 byte, vendor id
    pub const extended_query = 0x15; // 2 byte, offset in flash
    pub const alt_vendor = 0x17; // 2 byte, vendor id
    pub const alt_extended_query = 0x19; // 2 byte, offset in flash

    pub const vcc_lower_voltage = 0x1B; // BCD encoded u.l V
    pub const vcc_upper_voltage = 0x1C; // BCD encoded u.l V

    pub const vpp_lower_voltage = 0x1D; // BCD encoded u.l V
    pub const vpp_upper_voltage = 0x1E; // BCD encoded u.l V

    pub const device_density = 0x27; // 1 byte, 1<<val is size in bytes
    pub const bus_interface = 0x28; // 2 bytes, tells something about attachement
    pub const multi_byte_write_size = 0x2A; // 2 bytes, 1<<val is max number of bytes per write
    pub const num_erase_block_regions = 0x2C; // 1 byte, number of block groups with the same size

    pub fn blockRegionNumBlocks(i: u16) u16 {
        return 0x2D + 4 * i + 0;
    }
    pub fn blockRegionBlockSize(i: u16) u16 {
        return 0x2D + 4 * i + 2;
    }
};

fn translateBlockRegionBlockSize(value: u16) usize {
    return if (value == 0)
        128
    else
        256 * @as(usize, value);
}

fn translateBlockRegionBlockCount(value: u16) u32 {
    return value + 1;
}
