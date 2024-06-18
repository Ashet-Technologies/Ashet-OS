//!
//! A block device that resides in RAM. Can be read-only or read-write
//! depending on the initial configuration.
//!
//! Useful for initial ram disks and similar.
//!
const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.ramdisk);

const Driver = ashet.drivers.Driver;
const BlockDevice = ashet.drivers.BlockDevice;

pub const Access = enum { read_only, read_write };

pub fn RAM_Disk(comptime access: Access) type {
    return struct {
        const RDisk = @This();

        const BackingSlice = switch (access) {
            .read_only => []const u8,
            .read_write => []u8,
        };

        driver: Driver,
        slice: BackingSlice,

        pub fn init(slice: BackingSlice) RDisk {
            return RDisk{
                .driver = .{
                    .name = "RAM Disk",
                    .class = .{
                        .block = .{
                            .name = switch (access) {
                                .read_only => "RAM Disk (read-only)",
                                .read_write => "RAM Disk",
                            },
                            .block_size = 512,
                            .num_blocks = slice.len / 512,
                            .presentFn = isPresent,
                            .readFn = read,
                            .writeFn = write,
                        },
                    },
                },

                .slice = slice,
            };
        }

        pub fn isPresent(dri: *Driver) void {
            const disk: *RDisk = @fieldParentPtr("driver", dri);
            _ = disk;
            return true;
        }
        pub fn read(dri: *Driver, block_num: u32, buffer: []u8) BlockDevice.ReadError!void {
            const disk: *RDisk = @fieldParentPtr("driver", dri);

            const offset = 512 * block_num;
            std.mem.copyForwards(u8, buffer, disk.slice[offset..][0..512]);
        }

        pub fn write(dri: *Driver, block_num: u32, buffer: []const u8) BlockDevice.WriteError!void {
            const disk: *RDisk = @fieldParentPtr("driver", dri);

            const offset = 512 * block_num;
            std.mem.copyForwards(u8, disk.slice[offset..][0..512], buffer);
        }
    };
}
