const std = @import("std");
const ashet = @import("../main.zig");

pub const BlockDevice = struct {
    pub const DeviceError = error{ Fault, Timeout, InvalidBlock, DeviceNotPresent };
    pub const ReadError = DeviceError || error{};
    pub const WriteError = DeviceError || error{NotSupported};

    name: []const u8,
    block_size: u32, // typically 512
    num_blocks: u64 align(4), // number

    presentFn: *const fn (*ashet.drivers.Driver) bool,
    readFn: *const fn (*ashet.drivers.Driver, block: u64, []u8) ReadError!void,
    writeFn: *const fn (*ashet.drivers.Driver, block: u64, []const u8) WriteError!void,

    pub fn isPresent(dev: *BlockDevice) bool {
        return dev.presentFn(ashet.drivers.resolveDriver(.block, dev));
    }

    pub fn blockCount(dev: BlockDevice) u64 {
        return dev.num_blocks;
    }

    pub fn blockSize(dev: BlockDevice) usize {
        return dev.block_size;
    }

    pub fn byteSize(dev: BlockDevice) u64 {
        return dev.num_blocks * dev.block_size;
    }

    pub fn writeBlock(dev: *BlockDevice, block_num: u32, buffer: []const u8) WriteError!void {
        std.debug.assert(block_num < dev.num_blocks);
        std.debug.assert(buffer.len == dev.block_size);
        return dev.writeFn(ashet.drivers.resolveDriver(.block, dev), block_num, buffer);
    }

    pub fn readBlock(dev: *BlockDevice, block_num: u32, buffer: []u8) ReadError!void {
        std.debug.assert(block_num < dev.num_blocks);
        std.debug.assert(buffer.len == dev.block_size);
        const driver = ashet.drivers.resolveDriver(.block, dev);
        return dev.readFn(driver, block_num, buffer);
    }
};

pub fn enumerate() ashet.drivers.DriverIterator(.block) {
    return ashet.drivers.enumerate(.block);
}
