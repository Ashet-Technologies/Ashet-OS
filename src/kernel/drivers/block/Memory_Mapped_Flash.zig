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

const Memory_Mapped_Flash = @This();

pub const block_size = 512;

pub const Block = [block_size]u8;

driver: Driver,
blocks: []const Block,

pub fn init(offset: usize, length: usize) Memory_Mapped_Flash {
    return .{
        .driver = .{
            .name = "MMIO Flash",
            .class = .{
                .block = .{
                    .name = "FLASH",
                    .block_size = block_size,
                    .num_blocks = length / block_size,
                    .presentFn = isPresent,
                    .readFn = read,
                    .writeFn = write,
                },
            },
        },

        .blocks = @as([*]const Block, @ptrFromInt(offset))[0 .. length / block_size],
    };
}

pub fn isPresent(dri: *Driver) bool {
    _ = dri;
    return true;
}

pub fn read(dri: *Driver, block_num: u64, buffer: []u8) BlockDevice.ReadError!void {
    const disk: *Memory_Mapped_Flash = @alignCast(@fieldParentPtr("driver", dri));

    if (block_num >= disk.blocks.len)
        return error.InvalidBlock;

    const index: usize = @intCast(block_num);

    @memcpy(buffer, &disk.blocks[index]);
}

pub fn write(dri: *Driver, block_num: u64, buffer: []const u8) BlockDevice.WriteError!void {
    _ = dri;
    _ = block_num;
    _ = buffer;
    return error.NotSupported;
}
