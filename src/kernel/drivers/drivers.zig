const std = @import("std");

pub const block_device = struct {
    // pub const ata = @import("block-device/ata.zig");
    pub const CFI = @import("block-device/cfi.zig").CFI;
};
