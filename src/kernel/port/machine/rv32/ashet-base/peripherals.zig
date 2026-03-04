const std = @import("std");

const mmio = @import("../../../../main.zig").utils.mmio.mmioRegister;

// 0x40000000 - 0x4003DFFF   Framebuffer
// 0x40040000 - 0x40040FFF   Video Control
// 0x40041000 - 0x40041FFF   Debug Output
// 0x40042000 - 0x40042FFF   Keyboard
// 0x40043000 - 0x40043FFF   Mouse
// 0x40044000 - 0x40044FFF   Timer / RTC
// 0x40045000 - 0x40045FFF   System Info
// 0x40046000 - 0x40046FFF   Block Device 0
// 0x40047000 - 0x40047FFF   Block Device 1

pub const video_framebuffer: *volatile [256_000]u8 = @ptrFromInt(0x40000000);

pub const video_control = struct {
    pub const flush: *volatile u32 = @ptrFromInt(0x40040000);
};

pub const debug_output = struct {
    pub const tx: *volatile u8 = @ptrFromInt(0x40041000);
};

pub const system_info = struct {
    pub const ram_size: *const volatile u32 = @ptrFromInt(0x40045000);
};
