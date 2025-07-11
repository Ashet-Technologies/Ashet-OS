const std = @import("std");
const builtin = @import("builtin");

const ashet = @import("../../main.zig");
const storage = @import("../storage.zig");

const logger = std.log.scoped(.gpt_part);

const BlockDevice = storage.BlockDevice;

pub const GUID = ashet.abi.UUID;

pub const header_signature: [8]u8 = "EFI PART".*;

pub const gpt_revision: u32 = 0x0001_0000;

pub const HeaderBlock = extern struct {
    header: Header,
    padding: [420]u8 = @splat(0),
};

pub const Header = extern struct {
    signature: [8]u8 align(4) = header_signature,
    revision: u32 align(4) = gpt_revision,
    header_size: u32 align(4),
    header_crc: u32 align(4),
    reserved0: u32 align(4) = 0,
    primary_header_lba: u64 align(4),
    backup_header_lba: u64 align(4),
    first_part_lba: u64 align(4),
    last_part_lba: u64 align(4),
    disk_guid: GUID,
    part_table_lba: u64 align(4),
    part_count: u32 align(4),
    part_size: u32 align(4),
    part_table_crc: u32 align(4),
};

pub const Partition = extern struct {
    type_guid: GUID,
    part_guid: GUID,
    first_lba: u64,
    last_lba: u64,
    attributes: Attributes,
    name_utf16: [36]u16,

    pub const Attributes = packed struct(u64) {
        platform_required: bool,
        efi_ignored: bool,
        legacy_bootable: bool,
        reserved: u45 = 0,
        type_specific: u16,
    };
};

comptime {
    std.debug.assert(@sizeOf(GUID) == 16);
    std.debug.assert(@sizeOf(Header) == 92);
    std.debug.assert(@sizeOf(HeaderBlock) == 512);
    std.debug.assert(@sizeOf(Partition) == 128);
}
const parts_per_block = @divExact(512, @sizeOf(Partition));

pub const Iterator = struct {
    pub const InitError = error{
        UnsupportedBlockSize,
        DiskTooSmall,
        NoGptTable,
        UnsupportedGptRevision,
        CorruptedGptTable,
        ReadError,
    };

    part_buffer: [512]u8 align(16),

    bd: *BlockDevice,

    current_lba: u32,
    part_index: u32,
    part_count: u32,
    part_size: u32,

    pub fn init(bd: *BlockDevice) InitError!Iterator {
        if (bd.block_size != 512)
            return error.UnsupportedBlockSize;
        if (bd.num_blocks < 64)
            return error.DiskTooSmall;

        var header_block: HeaderBlock = undefined;
        std.debug.assert(@sizeOf(HeaderBlock) <= bd.block_size);

        bd.readBlock(1, std.mem.asBytes(&header_block)) catch |err| return map_bd_error(err);
        switch (builtin.cpu.arch.endian()) {
            .little => {},
            .big => std.mem.byteSwapAllFields(HeaderBlock, &header_block),
        }
        const header = &header_block.header;

        if (!std.mem.eql(u8, &header.signature, &header_signature)) {
            logger.info("Expected GPT signature '{}', but found '{}'.", .{
                std.fmt.fmtSliceEscapeUpper(&header_signature),
                std.fmt.fmtSliceEscapeUpper(&header.signature),
            });
            return error.NoGptTable;
        }

        if (header.revision != gpt_revision) {
            logger.warn("Unsupported GPT revision: {X}.{X}", .{
                0xFFFF & (header.revision >> 16),
                0xFFFF & (header.revision >> 0),
            });
            return error.UnsupportedGptRevision;
        }

        if (header.header_size != @sizeOf(Header)) {
            logger.warn("GPT header size mismatch. Expected {}, but found {}", .{
                @sizeOf(Header), header.header_size,
            });
            return error.UnsupportedGptRevision;
        }
        if (header.part_size != @sizeOf(Partition)) {
            logger.warn("GPT partition size mismatch. Expected {}, but found {}", .{
                @sizeOf(Partition), header.part_size,
            });
            return error.UnsupportedGptRevision;
        }

        const expected_crc: u32 = header.header_crc;
        header.header_crc = 0;
        const actual_crc: u32 = std.hash.crc.Crc32.hash(std.mem.asBytes(header));
        if (expected_crc != actual_crc) {
            logger.warn("GPT header checksum mismatch. Header encodes 0x{X:0>8}, but actually has 0x{X:0>8}", .{
                expected_crc,
                actual_crc,
            });
            return error.CorruptedGptTable;
        }

        if (header.backup_header_lba >= bd.num_blocks) {
            logger.warn("GPT backup LBA out of range. LBA is {}, but block count is {}", .{
                header.backup_header_lba,
                bd.num_blocks,
            });
            return error.CorruptedGptTable;
        }

        // TODO: Implement full backup header validation!

        return .{
            .bd = bd,
            .current_lba = std.math.cast(u32, header.part_table_lba) orelse return error.UnsupportedBlockSize,
            .part_index = 0,
            .part_count = header.part_count,
            .part_size = header.part_size,
            .part_buffer = undefined,
        };
    }

    pub fn next(iter: *Iterator) error{ReadError}!?Partition {
        while (true) {
            if (iter.part_index >= iter.part_count) {
                std.debug.assert(iter.part_index == iter.part_count);
                return null;
            }

            if (iter.part_index % parts_per_block == 0) {
                iter.bd.readBlock(iter.current_lba, &iter.part_buffer) catch |err| return map_bd_error(err);
                iter.current_lba += 1;
            }

            const partitions: [*]Partition = @ptrCast(&iter.part_buffer);
            const partition = &partitions[iter.part_index % parts_per_block];
            switch (builtin.cpu.arch.endian()) {
                .little => {},
                .big => std.mem.byteSwapAllFields(Partition, partition),
            }

            iter.part_index += 1;

            if (partition.type_guid.eql(&part_types.unused)) {
                // skip unused parts
                continue;
            }

            return partition.*;
        }
    }

    fn map_bd_error(err: BlockDevice.ReadError) error{ReadError} {
        logger.debug("mapping block device error {} to error.ReadError", .{err});
        return error.ReadError;
    }
};

pub const part_types = struct {
    pub const unused = GUID.nil;
    pub const efi_system_partition = GUID.constant("C12A7328-F81F-11D2-BA4B-00A0C93EC93B");
    pub const bios_boot_partition = GUID.constant("21686148-6449-6E6F-744E-656564454649");
    pub const microsoft_basic_data = GUID.constant("EBD0A0A2-B9E5-4433-87C0-68B6B72699C7");
    pub const linux_file_system = GUID.constant("0FC63DAF-8483-4772-8E79-3D69D8477DE4");
    pub const linux_lvm_partition = GUID.constant("E6D6D379-F507-44C2-A23C-238F2A3DF928");
    pub const linux_luks_partition = GUID.constant("CA7D7CCB-63ED-4C53-861C-1742536059CC");

    // Shoutout to https://www.guidgenerator.com/
    pub const ashet_rootfs = GUID.constant("1b279432-2c0a-4d6c-aa30-7edee4b7155f");
};
