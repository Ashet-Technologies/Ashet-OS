const std = @import("std");
const utils = @import("utils.zig");
const virtio = @import("virtio.zig");

pub const request_block_size = 512;

pub const Config = extern struct {
    capacity: utils.le64,
    size_max: utils.le32,
    seg_max: utils.le32,
    geometry: Geometry,
    block_size: utils.le32,
    topology: Topology,
    writeback: u8,
    unused0: [3]u8,
    max_discard_sectors: utils.le32,
    max_discard_seg: utils.le32,
    discard_sector_alignment: utils.le32,
    max_write_zeroes_sectors: utils.le32,
    max_write_zeroes_seg: utils.le32,
    write_zeroes_may_unmap: u8,
    unused1: [3]u8,
};

pub const Geometry = extern struct {
    cylinders: utils.le16,
    heads: u8,
    sectors: u8,
};

pub const Topology = extern struct {
    /// # of logical blocks per physical block (log2)
    physical_block_exp: u8,

    /// offset of first aligned logical block
    alignment_offset: u8,

    /// suggested minimum I/O size in blocks
    min_io_size: utils.le16,

    /// optimal (suggested maximum) I/O size in blocks
    opt_io_size: utils.le32,
};

// pub const Request = extern struct {
//     type: utils.le32, // RequestType
//     reserved: utils.le32,
//     /// The sector number indicates the offset (multiplied by 512) where the read or write is to occur. This field is
//     /// unused and set to 0 for commands other than read or write.
//     sector: utils.le64,
//     data: [*]u8, // u8 data[];

//     /// The final status byte is written by the device: either VIRTIO_BLK_S_OK for success, VIRTIO_BLK_S_-
//     /// IOERR for device or driver error or VIRTIO_BLK_S_UNSUPP for a request unsupported by device:
//     status: u8,
// };

pub const RequestHeader = extern struct {
    type: utils.le32, // RequestType
    reserved: utils.le32,
    /// The sector number indicates the offset (multiplied by 512) where the read or write is to occur. This field is
    /// unused and set to 0 for commands other than read or write.
    sector: utils.le64,
    // data: [request_block_size * options.block_count]u8, // u8 data[];

};

pub const RequestResponse = extern struct {
    /// The final status byte is written by the device: either VIRTIO_BLK_S_OK for success, VIRTIO_BLK_S_-
    /// IOERR for device or driver error or VIRTIO_BLK_S_UNSUPP for a request unsupported by device:
    status: Status,
};

pub const Status = enum(u8) {
    ok = 0,
    io_error = 1,
    unsupported = 2,

    initial = 0xFF,
    _,
};

pub const RequestType = enum(u32) {
    /// VIRTIO_BLK_T_IN requests populate data with the contents of sectors read from the block device (in multiples of 512 bytes).
    in = 0,

    /// VIRTIO_BLK_T_OUT requests write the contents of data to the block device (in multiples of 512 bytes).
    out = 1,

    flush = 4,

    discard = 11,

    write_zeroes = 13,

    _,
};

/// The data used for discard or write zeroes commands consists of one or more segments. The maximum
/// number of segments is max_discard_seg for discard commands and max_write_zeroes_seg for write zeroes
/// commands. Each segment is of form:
pub const DiscardWriteZeroesParameter = extern struct {
    /// sector indicates the starting offset (in 512-byte units) of the segment
    sector: utils.le64,
    /// while num_sectors indicates the number of sectors in each discarded range.
    num_sectors: utils.le32,
    /// unmap is only used in write zeroes commands and allows the device
    /// to discard the specified range, provided that following reads return zeroes.
    flags: utils.le32, // 0x01 = unmap
};

pub const FeatureFlag = struct {
    /// legacy: Device supports request barriers.
    pub const barrier = virtio.FeatureFlag.new(0);

    /// Maximum size of any single segment is in size_max.
    pub const size_max = virtio.FeatureFlag.new(1);

    /// Maximum number of segments in a request is in seg_max.
    pub const seg_max = virtio.FeatureFlag.new(2);

    /// Disk-style geometry specified in geometry.
    pub const geometry = virtio.FeatureFlag.new(4);

    /// Device is read-only.
    pub const ro = virtio.FeatureFlag.new(5);

    /// Block size of disk is in blk_size.
    pub const block_size = virtio.FeatureFlag.new(6);

    /// legacy: Device supports scsi packet commands.
    pub const scsi = virtio.FeatureFlag.new(7);

    /// Cache flush command support.
    pub const flush = virtio.FeatureFlag.new(9);

    ///  Device exports information on optimal I/O alignment.
    pub const topology = virtio.FeatureFlag.new(10);

    ///  Device can toggle its cache between writeback and writethrough modes.
    pub const config_wce = virtio.FeatureFlag.new(11);

    ///  Device can support discard command, maximum discard sectors size in max_discard_sectors and maximum discard segment number in max_discard_seg.
    pub const discard = virtio.FeatureFlag.new(13);

    ///  Device can support write zeroes command, maximum write zeroes sectors size in max_write_zeroes_sectors and maximum write zeroes segment number in max_write_zeroes_seg.
    pub const write_zeroes = virtio.FeatureFlag.new(14);
};
