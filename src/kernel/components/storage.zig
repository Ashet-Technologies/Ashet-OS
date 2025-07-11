const std = @import("std");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.storage);

const mbr_part = @import("storage/mbr_part.zig");
const gpt_part = @import("storage/gpt_part.zig");

pub const Tags = packed struct(u8) {
    root_fs: bool,
    partitioned: bool,
    _reserved: u6 = 0,
};

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

    tags: Tags = .{
        .root_fs = false,
        .partitioned = false,
    },

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

    pub fn writeBlock(dev: *BlockDevice, block_num: u64, buffer: []const u8) WriteError!void {
        std.debug.assert(block_num < dev.num_blocks);
        std.debug.assert(buffer.len == dev.block_size);
        logger.debug("write block {}: {}", .{
            block_num,
            std.fmt.fmtSliceHexUpper(buffer),
        });
        return dev.writeFn(ashet.drivers.resolveDriver(.block, dev), block_num, buffer);
    }

    pub fn readBlock(dev: *BlockDevice, block_num: u64, buffer: []u8) ReadError!void {
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
            driver.tags.partitioned = true;

            continue;
        } else |err| switch (err) {
            // These errors are ok, as they signal that we either don't have a supported disk
            // or the disk does not contain partitions
            error.NoGptTable, error.UnsupportedBlockSize, error.DiskTooSmall => |e| {
                logger.info("skip GPT for {s}: {s}", .{ driver.name, @errorName(e) });
            },

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

            error.OutOfMemory => {
                logger.err("failed to allocate data for partition data, aborting scan.", .{});
                return;
            },
        }

        if (detect_mbr_parts(driver)) |_| {
            // successfully detected GPT partitions
            driver.tags.partitioned = true;
            continue;
        } else |err| switch (err) {
            // These errors are ok, as they signal that we either don't have a supported disk
            // or the disk does not contain partitions
            error.NoMbrTable, error.UnsupportedBlockSize, error.DiskTooSmall => |e| {
                logger.info("skip MBR for {s}: {s}", .{ driver.name, @errorName(e) });
            },

            error.ReadError => {
                logger.err("failed to read GPT partition table data", .{});
                continue;
            },

            error.OutOfMemory => {
                logger.err("failed to allocate data for partition data, aborting scan.", .{});
                return;
            },
        }
    }
}

fn detect_mbr_parts(bd: *BlockDevice) !void {
    var iter: mbr_part.Iterator = try .init(bd);

    var index: u32 = 0;
    while (try iter.next()) |part| : (index += 1) {
        logger.info("partition found: {}", .{part});

        const part_dev = try create_partition(bd, index, part.first_lba, part.last_lba - part.first_lba + 1);

        if (part.part_type == .ashet_os) {
            part_dev.driver.class.block.tags.root_fs = true;
        }
    }

    if (index == 0) {
        logger.warn("MBR table is empty? Maybe just a protective MBR?", .{});
        return error.NoMbrTable;
    }
}

fn detect_gpt_parts(bd: *BlockDevice) !void {
    var iter: gpt_part.Iterator = try .init(bd);

    var index: u32 = 0;
    while (try iter.next()) |part| : (index += 1) {
        logger.info("partition found: {}", .{part});

        if (part.type_guid.eql(gpt_part.part_types.bios_boot_partition)) {
            logger.warn("skipping BIOS boot partition...", .{});
            continue;
        }

        const part_dev = try create_partition(bd, index, part.first_lba, part.last_lba - part.first_lba + 1);
        if (part.type_guid.eql(gpt_part.part_types.ashet_rootfs)) {
            part_dev.driver.class.block.tags.root_fs = true;
        }
    }
}

fn create_partition(bd: *BlockDevice, index: u32, base_lba: u64, block_count: u64) !*PartitionDevice {
    const part_name = try std.fmt.allocPrint(ashet.memory.static_memory_allocator, "{s}.{}", .{ bd.name, index });

    logger.info("created partition {s} for block device {s}", .{ part_name, bd.name });

    const pdev = try ashet.memory.static_memory_allocator.create(PartitionDevice);
    pdev.* = .{
        .driver = .{
            .name = "Disk Partition",
            .class = .{
                .block = .{
                    .block_size = bd.block_size,
                    .name = part_name,
                    .num_blocks = block_count,
                    .presentFn = PartitionDevice.present,
                    .readFn = PartitionDevice.read,
                    .writeFn = PartitionDevice.write,
                },
            },
        },
        .device = bd,
        .base_block = base_lba,
        .index = index,
    };
    ashet.drivers.install(&pdev.driver);
    return pdev;
}

const PartitionDevice = struct {
    driver: ashet.drivers.Driver,
    device: *BlockDevice,

    index: u32,
    base_block: u64,

    fn present(driver: *ashet.drivers.Driver) bool {
        const part: *PartitionDevice = @alignCast(@fieldParentPtr("driver", driver));
        return part.device.isPresent();
    }

    fn read(driver: *ashet.drivers.Driver, block: u64, data: []u8) ashet.storage.BlockDevice.ReadError!void {
        const part: *PartitionDevice = @alignCast(@fieldParentPtr("driver", driver));
        if (block >= part.driver.class.block.num_blocks)
            return error.InvalidBlock;
        return try part.device.readBlock(part.base_block + block, data);
    }

    fn write(driver: *ashet.drivers.Driver, block: u64, data: []const u8) ashet.storage.BlockDevice.WriteError!void {
        const part: *PartitionDevice = @alignCast(@fieldParentPtr("driver", driver));
        if (block >= part.driver.class.block.num_blocks)
            return error.InvalidBlock;
        return try part.device.writeBlock(part.base_block + block, data);
    }
};
