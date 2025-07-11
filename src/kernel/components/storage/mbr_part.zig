const std = @import("std");
const builtin = @import("builtin");

const ashet = @import("../../main.zig");
const storage = @import("../storage.zig");

const logger = std.log.scoped(.mbr_part);

const BlockDevice = storage.BlockDevice;

pub const MasterBootRecord = extern struct {
    bootcode: [446]u8,
    partitions: [4]MbrPartition,
    sig_0x55: u8,
    sig_0xAA: u8,
};

const MbrPartition = extern struct {
    status: StatusFlags,
    first_chs: EncodedCHS,
    part_type: PartType,
    last_chs: EncodedCHS,
    first_lba: u32 align(1),
    sector_cnt: u32 align(1),

    pub const StatusFlags = packed struct(u8) {
        _reserved: u7 = 0,

        bootable: bool,
    };

    pub const EncodedCHS = extern struct {
        head: u8,
        sector_cylh: packed struct(u8) {
            sector: u6,
            cyl_high: u2,
        },
        cyl_low: u8,
    };
};

pub const Partition = struct {
    part_type: PartType,

    first_lba: u32,
    last_lba: u32,

    first_chs: CHS,
    last_chs: CHS,

    bootable: bool,
};

pub const CHS = packed struct(u24) {
    cylinder: u10,
    head: u8,
    sector: u6,

    fn from_encoded(enc: MbrPartition.EncodedCHS) CHS {
        return .{
            .cylinder = (@as(u10, enc.sector_cylh.cyl_high) << 8) | enc.cyl_low,
            .head = enc.head,
            .sector = enc.sector_cylh.sector,
        };
    }

    pub fn format(chs: CHS, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("CHS({}:{}:{})", .{
            chs.cylinder, chs.head, chs.sector,
        });
    }
};

comptime {
    std.debug.assert(@sizeOf(MbrPartition) == 16);
    std.debug.assert(@sizeOf(MasterBootRecord) == 512);

    std.debug.assert(@offsetOf(MasterBootRecord, "bootcode") == 0x0000);
    std.debug.assert(@offsetOf(MasterBootRecord, "partitions") == 0x01BE);
    std.debug.assert(@offsetOf(MasterBootRecord, "sig_0x55") == 0x01FE);
    std.debug.assert(@offsetOf(MasterBootRecord, "sig_0xAA") == 0x01FF);
}

pub const Iterator = struct {
    pub const InitError = error{
        UnsupportedBlockSize,
        DiskTooSmall,
        ReadError,
        NoMbrTable,
    };

    mbr: MasterBootRecord,

    bd: *BlockDevice,

    part_index: usize,

    pub fn init(bd: *BlockDevice) InitError!Iterator {
        if (bd.block_size != 512)
            return error.UnsupportedBlockSize;
        if (bd.num_blocks < 4)
            return error.DiskTooSmall;

        var mbr: MasterBootRecord = undefined;
        std.debug.assert(@sizeOf(MasterBootRecord) <= bd.block_size);

        bd.readBlock(0, std.mem.asBytes(&mbr)) catch |err| return map_bd_error(err);
        switch (builtin.cpu.arch.endian()) {
            .little => {},
            .big => std.mem.byteSwapAllFields(MasterBootRecord, &mbr),
        }

        if (mbr.sig_0x55 != 0x55 or mbr.sig_0xAA != 0xAA) {
            logger.info("Expected MBR signature '55 AA', but found '{X:0>2} {X:0>2}'.", .{
                mbr.sig_0x55,
                mbr.sig_0xAA,
            });
            return error.NoMbrTable;
        }

        // TODO: Implement full backup header validation!

        return .{
            .bd = bd,
            .mbr = mbr,
            .part_index = 0,
        };
    }

    pub fn next(iter: *Iterator) error{ReadError}!?Partition {
        while (true) {
            if (iter.part_index >= iter.mbr.partitions.len) {
                std.debug.assert(iter.part_index == iter.mbr.partitions.len);
                return null;
            }
            const part = &iter.mbr.partitions[iter.part_index];
            iter.part_index += 1;
            if (part.part_type == .empty) {
                continue;
            }

            if (part.part_type.is_extended_boot_record()) {
                // TODO: Implement EBR support
                // See also: https://en.wikipedia.org/wiki/Extended_boot_record
                logger.info("TODO: Implement support for EBR sub-partitions. Partition Entry: {}", .{
                    part,
                });
                continue;
            }

            // logger.info("raw part data {}", .{part});

            return .{
                .bootable = part.status.bootable,
                .part_type = part.part_type,

                .first_lba = part.first_lba,
                .last_lba = part.first_lba + part.sector_cnt -| 1,

                .first_chs = .from_encoded(part.first_chs),
                .last_chs = .from_encoded(part.last_chs),
            };
        }
    }

    fn map_bd_error(err: BlockDevice.ReadError) error{ReadError} {
        logger.debug("mapping block device error {} to error.ReadError", .{err});
        return error.ReadError;
    }
};

pub const PartType = enum(u8) {
    // Sourced from https://en.wikipedia.org/wiki/Partition_type#List_of_partition_IDs

    /// Empty partition entry
    /// Type: Free
    empty = 0x00,

    /// Ashet OS uses the partition type 0x7F to identify it's own root partition.
    ///
    /// Reserved for individual or local use and temporary or experimental projects[2]
    ashet_os = 0x7F,

    _,

    pub fn is_extended_boot_record(pt: PartType) bool {
        return switch (@intFromEnum(pt)) {
            0x05, // Extended partition with CHS addressing.
            0x0F, // Extended partition with LBA
            0x15, // Hidden extended partition with CHS addressing
            0x1F, // Hidden extended partition with LBA addressing
            0x42, // Dynamic extended partition marker
            0x91, // Hidden extended partition with CHS addressing
            0x9B, // Hidden extended partition with LBA
            0xC5, // Secured extended partition with CHS addressing
            0xCF, // Secured extended partition with LBA
            0xD5, // Secured extended partition with CHS addressing

            => true,

            else => false,
        };
    }
};
