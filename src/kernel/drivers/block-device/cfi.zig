const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.@"block-device cfi");

const Interface = ashet.storage.BlockDevice.Interface;

pub const CFI = union(enum) {
    u8: CfiDeviceImpl(u8),
    u16: CfiDeviceImpl(u16),
    u32: CfiDeviceImpl(u32),

    pub fn init(offset: usize, length: usize) error{InvalidDevice}!CFI {
        inline for ([_]type{ u8, u16, u32 }) |T| {
            const flash_mem = @intToPtr([*]T, offset);

            flash_mem[0x55] = 0x98; // enter CFI interface
            const seq = [3]u8{
                @truncate(u8, flash_mem[0x10]),
                @truncate(u8, flash_mem[0x11]),
                @truncate(u8, flash_mem[0x12]),
            };
            flash_mem[0x55] = 0xFF; // return to read array mode

            if (std.mem.eql(u8, &seq, "QRY")) {
                return @unionInit(CFI, @typeName(T), try CfiDeviceImpl(T).init(flash_mem, length));
            }
        }
        return error.InvalidDevice;
    }

    pub fn interface(self: *CFI) *Interface {
        return switch (self.*) {
            .u8 => |*v| &v.block_device,
            .u16 => |*v| &v.block_device,
            .u32 => |*v| &v.block_device,
        };
    }

    pub fn CfiDeviceImpl(comptime InterfaceWidth: type) type {
        return struct {
            const Impl = @This();

            block_device: Interface,
            base: [*]InterfaceWidth,
            byte_size: usize,

            fn init(base: [*]InterfaceWidth, byte_size: usize) error{}!Impl {
                var cfi = Impl{
                    .block_device = .{
                        .block_size = 512,
                        .num_blocks = byte_size / 512,

                        .presentFn = present,
                        .readFn = read,
                        .writeFn = write,
                    },

                    .base = base,
                    .byte_size = byte_size,

                    //
                };

                {
                    cfi.enterMode(.cfi_query);
                    defer cfi.enterMode(.array_read);

                    // TODO: Query all information

                    const vendor = cfi.readRegister(u16, regs.vendor);
                    const extended_query = cfi.readRegister(u16, regs.extended_query);

                    logger.info("vendor                  = 0x{X:0>4}", .{vendor});
                    logger.info("extended_query          = 0x{X:0>4}", .{extended_query});
                    logger.info("alt_vendor              = 0x{X:0>4}", .{cfi.readRegister(u16, regs.alt_vendor)});
                    logger.info("alt_extended_query      = 0x{X:0>4}", .{cfi.readRegister(u16, regs.alt_extended_query)});
                    logger.info("vcc_lower_voltage       = 0x{X:0>2}", .{cfi.readRegister(u8, regs.vcc_lower_voltage)});
                    logger.info("vcc_upper_voltage       = 0x{X:0>2}", .{cfi.readRegister(u8, regs.vcc_upper_voltage)});
                    logger.info("vpp_lower_voltage       = 0x{X:0>2}", .{cfi.readRegister(u8, regs.vpp_lower_voltage)});
                    logger.info("vpp_upper_voltage       = 0x{X:0>2}", .{cfi.readRegister(u8, regs.vpp_upper_voltage)});
                    logger.info("device_density          = 2^{d}", .{cfi.readRegister(u8, regs.device_density)});
                    logger.info("bus_interface           = 0x{X:0>4}", .{cfi.readRegister(u16, regs.bus_interface)});
                    logger.info("multi_byte_write_size   = 2^{d}", .{cfi.readRegister(u16, regs.multi_byte_write_size)});

                    const regions = cfi.readRegister(u8, regs.num_erase_block_regions);
                    logger.info("num_erase_block_regions = {d}", .{regions});
                    for (@as([*]void, undefined)[0..regions]) |_, i| {
                        logger.info("  region[{}].block count = {d}", .{ i, translateBlockRegionBlockCount(cfi.readRegister(u16, regs.blockRegionNumBlocks(@truncate(u16, i)))) });
                        logger.info("  region[{}].block_size  = {d}", .{ i, std.fmt.fmtIntSizeBin(translateBlockRegionBlockSize(cfi.readRegister(u16, regs.blockRegionBlockSize(@truncate(u16, i))))) });
                    }

                    if (extended_query != 0) {
                        logger.info("ext query                = {c}{c}{c}", .{
                            cfi.readRegister(u8, extended_query + 0),
                            cfi.readRegister(u8, extended_query + 1),
                            cfi.readRegister(u8, extended_query + 2),
                        });
                        logger.info("version                  = {c}.{c}", .{
                            cfi.readRegister(u8, extended_query + 3),
                            cfi.readRegister(u8, extended_query + 4),
                        });
                    }
                }
                return cfi;
            }

            pub fn enterMode(self: *Impl, mode: Mode) void {
                self.base[0x55] = @enumToInt(mode);
            }

            pub fn readRegister(self: Impl, comptime T: type, reg: u16) T {
                var bytes: [@sizeOf(T)]u8 = undefined;
                for (bytes) |*b, i| {
                    b.* = @truncate(u8, self.base[reg + i]);
                }
                return std.mem.readIntLittle(T, &bytes);
            }

            fn present(intf: *Interface) bool {
                const self = @fieldParentPtr(Impl, "block_device", intf);
                _ = self;
                return true;
            }

            fn read(intf: *Interface, block: u64, data: []align(4) u8) ashet.storage.BlockDevice.ReadError!void {
                const self = @fieldParentPtr(Impl, "block_device", intf);

                const block_items = self.block_device.block_size / @sizeOf(InterfaceWidth);
                const block_start = std.math.cast(usize, block_items * block) orelse return error.InvalidBlock;
                const block_end = block_start + block_items;

                self.enterMode(.array_read);
                std.mem.copy(
                    InterfaceWidth,
                    std.mem.bytesAsSlice(InterfaceWidth, data),
                    self.base[block_start..block_end],
                );
            }

            fn write(intf: *Interface, block: u64, data: []align(4) const u8) ashet.storage.BlockDevice.WriteError!void {
                const self = @fieldParentPtr(Impl, "block_device", intf);

                // we cannot write 256 byte blocks on 8 bit address bus
                if (@sizeOf(InterfaceWidth) == 1)
                    return error.NotSupported;

                const block_items = std.math.cast(InterfaceWidth, self.block_device.block_size / @sizeOf(InterfaceWidth)) orelse return error.NotSupported;
                const block_start = std.math.cast(InterfaceWidth, block_items * block) orelse return error.InvalidBlock;
                const block_end = block_start + block_items;

                // WARNING: THIS IS ONLY VALID FOR THE QEMU PFLASH1!
                // Reference: ${QEMU_SRC}/hw/block/pflash_cfi01.c

                self.enterMode(.write_to_buffer); // 0xE8
                defer self.enterMode(.array_read);

                const prog_error = 0x10;

                if ((self.base[0x55] & prog_error) != 0)
                    return error.Fault;

                self.base[0x55] = block_items; // write block size in interface width

                if ((self.base[0x55] & prog_error) != 0)
                    return error.Fault;

                std.mem.copy(
                    InterfaceWidth,
                    self.base[block_start..block_end],
                    std.mem.bytesAsSlice(InterfaceWidth, data),
                );

                if ((self.base[0x55] & prog_error) != 0)
                    return error.Fault;

                self.base[0x55] = 0xD0; // confirm

                if ((self.base[0x55] & prog_error) != 0)
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
};
