const std = @import("std");

pub const block_device = struct {
    // pub const ata = @import("block-device/ata.zig");
    pub const CFI = @import("block-device/cfi.zig").CFI;
};

pub const serial = struct {
    pub const ns16c550 = @import("serial/ns16c550.zig");
};

pub const rtc = struct {
    pub const Goldfish = @import("rtc/goldfish.zig").GoldfishRTC;
};
