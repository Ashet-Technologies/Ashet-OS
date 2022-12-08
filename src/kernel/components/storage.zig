const std = @import("std");
const ashet = @import("../main.zig");

pub const BlockDevice = struct {
    pub const DeviceError = error{InvalidBlock};
    pub const ReadError = DeviceError || error{};
    pub const WriteError = DeviceError || error{ Fault, NotSupported };

    name: []const u8,
    interface: *Interface,

    pub const Interface = struct {
        block_size: u32, // typically 512
        num_blocks: u64, // number

        presentFn: std.meta.FnPtr(fn (*Interface) bool),
        readFn: std.meta.FnPtr(fn (*Interface, block: u64, []u8) ReadError!void),
        writeFn: std.meta.FnPtr(fn (*Interface, block: u64, []const u8) WriteError!void),
    };

    pub fn isPresent(dev: BlockDevice) bool {
        return dev.interface.presentFn(dev.interface);
    }

    pub fn blockCount(dev: BlockDevice) u64 {
        return dev.interface.num_blocks;
    }

    pub fn blockSize(dev: BlockDevice) usize {
        return dev.interface.block_size;
    }

    pub fn byteSize(dev: BlockDevice) u64 {
        return dev.interface.num_blocks * dev.interface.block_size;
    }

    pub fn writeBlock(dev: BlockDevice, block_num: u32, buffer: []const u8) WriteError!void {
        std.debug.assert(buffer.len == dev.interface.block_size);
        return dev.interface.writeFn(dev.interface, block_num, buffer);
    }

    pub fn readBlock(dev: BlockDevice, block_num: u32, buffer: []u8) ReadError!void {
        std.debug.assert(buffer.len == dev.interface.block_size);
        return dev.interface.readFn(dev.interface, block_num, buffer);
    }
};

pub fn enumerate() BlockDeviceEnumerator {
    return BlockDeviceEnumerator{};
}

pub const BlockDeviceEnumerator = struct {
    index: usize = 0,

    pub fn next(self: *BlockDeviceEnumerator) ?BlockDevice {
        // TODO: Fetch from block drivers
        _ = self;
        return null;
        // const list = hal.storage.devices;
        // if (self.index >= list.len)
        //     return null;
        // const item = list[self.index];
        // self.index += 1;
        // return item;
    }
};
