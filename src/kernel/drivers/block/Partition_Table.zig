//!
//! A proxy block device that will scan another block device for
//! partitions and will expose the partitions as sub-devices.
//!
//! This partition table implements a MBR partition table.
//!
const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.partition_table);

const Partition_Table = @This();
const Driver = ashet.drivers.Driver;

// TODO: Implement the partition table
