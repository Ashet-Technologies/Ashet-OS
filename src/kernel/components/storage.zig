const std = @import("std");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.storage);

const mbr_part = @import("storage/mbr_part.zig");
const gtp_part = @import("storage/gpt_part.zig");

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
        logger.debug("write block {}: {}", .{
            block_num,
            std.fmt.fmtSliceHexUpper(buffer),
        });
        return dev.writeFn(ashet.drivers.resolveDriver(.block, dev), block_num, buffer);
    }

    pub fn readBlock(dev: *BlockDevice, block_num: u32, buffer: []u8) ReadError!void {
        std.debug.assert(block_num < dev.num_blocks);
        std.debug.assert(buffer.len == dev.block_size);
        logger.debug("read block {}...", .{
            block_num,
        });
        const driver = ashet.drivers.resolveDriver(.block, dev);

        const result = dev.readFn(driver, block_num, buffer);
        logger.debug("... => {}", .{std.fmt.fmtSliceHexUpper(buffer)});
        return result;
    }
};

pub fn enumerate() ashet.drivers.DriverIterator(.block) {
    return ashet.drivers.enumerate(.block);
}

pub fn scan_partition_tables() void {
    var iter = enumerate();

    while (iter.next()) |driver| {
        if (!driver.isPresent())
            continue;
        logger.info("scanning {s} ...", .{driver.name});
        if (detect_gpt_parts(driver)) |_| {
            // successfully detected GPT partitions
            continue;
        } else |err| switch (err) {
            // These errors are ok, as they signal that we either don't have a supported disk
            // or the disk does not contain partitions
            error.NoGptTable, error.UnsupportedBlockSize, error.DiskTooSmall => {},

            error.UnsupportedGptRevision => {
                logger.warn("skipping block device {s} partitions, contains unsupported GPT partition table", .{driver.name});
                continue;
            },
            error.CorruptedGptTable => {
                logger.err("skipping block device {s} partitions, contains corrupt GPT partition table", .{driver.name});
                continue;
            },

            error.ReadError => {
                logger.err("failed to read GPT partition table data", .{});
                continue;
            },
        }

        if (detect_mbr_parts(driver)) |_| {
            // successfully detected GPT partitions
            continue;
        } else |err| switch (err) {
            //
        }
    }
}

fn detect_mbr_parts(bd: *BlockDevice) !void {
    //
    _ = bd;
}

fn detect_gpt_parts(bd: *BlockDevice) !void {
    var iter: gtp_part.Iterator = try .init(bd);

    while (try iter.next()) |part| {
        logger.info("partition found: {}", .{part});
    }
}
