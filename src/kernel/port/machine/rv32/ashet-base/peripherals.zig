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

pub const video_framebuffer: *align(4096) volatile [256_000]u8 = @ptrFromInt(0x40000000);

pub const video_control: *volatile VideoControl = @ptrFromInt(0x40040000);

pub const debug_output: *volatile DebugOutput = @ptrFromInt(0x40041000);

pub const keyboard: *volatile InputEventDevice = @ptrFromInt(0x40042000);

pub const mouse: *volatile InputEventDevice = @ptrFromInt(0x40043000);

pub const timer: *volatile Timer = @ptrFromInt(0x40044000);

pub const system_info: *volatile SystemInfo = @ptrFromInt(0x40045000);

pub const block_device_0: *volatile BlockDevice = @ptrFromInt(0x40046000);

pub const block_device_1: *volatile BlockDevice = @ptrFromInt(0x40047000);

pub const VideoControl = extern struct {
    flush: u32, // WO

    comptime {
        std.debug.assert(@offsetOf(@This(), "flush") == 0);
    }
};

pub const DebugOutput = extern struct {
    tx: u8, // WO

    comptime {
        std.debug.assert(@offsetOf(@This(), "tx") == 0);
    }
};

/// Input Event Device — shared register layout for Keyboard and Mouse.
/// STATUS at +0x00, DATA at +0x04. Both read-only.
pub const InputEventDevice = extern struct {
    /// Bit 0 = at least one entry waiting in FIFO
    status: packed struct(u32) {
        ready: bool,
        _reserved: u31 = 0,
    },
    /// Pop and return one entry (0x00000000 if FIFO empty).
    /// Interpretation depends on the device type.
    data: u32,

    comptime {
        std.debug.assert(@offsetOf(@This(), "status") == 0x00);
        std.debug.assert(@offsetOf(@This(), "data") == 0x04);
    }

    /// Keyboard event encoding: bit 31 = key_down, bits [15:0] = HID usage code.
    pub const KeyboardEvent = packed struct(u32) {
        usage_code: u16,
        _reserved: u15 = 0,
        key_down: bool,
    };

    /// Mouse event types, encoded in bits [31:30].
    pub const MouseEventType = enum(u2) {
        /// Absolute pointing: bits [23:12] = X (u12), bits [11:0] = Y (u12)
        pointing = 0b00,
        /// Button down: bits [15:0] = button ID
        button_down = 0b01,
        /// Button up: bits [15:0] = button ID
        button_up = 0b10,
    };

    pub const MouseButton = enum(u16) {
        left = 0,
        right = 1,
        middle = 2,
    };

    pub const MouseEvent = packed struct(u32) {
        payload: u30,
        event_type: MouseEventType,

        pub fn asPointing(self: MouseEvent) struct { x: u12, y: u12 } {
            return .{
                .x = @truncate(self.payload >> 12),
                .y = @truncate(self.payload),
            };
        }

        pub fn asButton(self: MouseEvent) MouseButton {
            return @enumFromInt(@as(u16, @truncate(self.payload)));
        }
    };
};

pub const Timer = extern struct {
    /// Low 32 bits of monotonic time (microseconds since start); reading latches mtime_hi
    mtime_lo: u32,
    /// High 32 bits of monotonic time (latched value from last mtime_lo read)
    mtime_hi: u32,

    _reserved0: u32,
    _reserved1: u32,

    /// Low 32 bits of RTC Unix timestamp; reading latches rtc_hi
    rtc_lo: u32,
    /// High 32 bits of RTC Unix timestamp (latched value from last rtc_lo read)
    rtc_hi: u32,

    pub fn read_mtime_us(instance: *volatile Timer) u64 {
        const lo = instance.mtime_lo;
        const hi = instance.mtime_hi;
        return (@as(u64, hi) << 32) | lo;
    }

    pub fn read_rtc(instance: *volatile Timer) u64 {
        const lo = instance.rtc_lo;
        const hi = instance.rtc_hi;
        return (@as(u64, hi) << 32) | lo;
    }

    comptime {
        std.debug.assert(@offsetOf(@This(), "mtime_lo") == 0x00);
        std.debug.assert(@offsetOf(@This(), "mtime_hi") == 0x04);
        std.debug.assert(@offsetOf(@This(), "rtc_lo") == 0x10);
        std.debug.assert(@offsetOf(@This(), "rtc_hi") == 0x14);
    }
};

pub const SystemInfo = extern struct {
    /// Total RAM in bytes
    ram_size: u32,

    comptime {
        std.debug.assert(@offsetOf(@This(), "ram_size") == 0x00);
    }
};

pub const BlockDevice = extern struct {
    status: packed struct(u32) {
        /// Device is present
        present: bool,
        /// Device is busy
        busy: bool,
        /// Last operation failed
        @"error": bool,
        _reserved: u29,
    },
    /// Total number of 512-byte blocks
    size: u32,
    /// Target logical block address
    lba: u32,
    /// 1 = read, 2 = write, 3 = clear error flag
    command: Command,
    /// Reserved gap (0x010–0x0FF)
    _reserved: [0xF0]u8,
    /// 512-byte transfer buffer
    buffer: [512]u8,

    pub const Command = enum(u32) {
        read = 1,
        write = 2,
        clear_error = 3,
        _,
    };

    comptime {
        std.debug.assert(@offsetOf(@This(), "status") == 0x000);
        std.debug.assert(@offsetOf(@This(), "size") == 0x004);
        std.debug.assert(@offsetOf(@This(), "lba") == 0x008);
        std.debug.assert(@offsetOf(@This(), "command") == 0x00C);
        std.debug.assert(@offsetOf(@This(), "buffer") == 0x100);
    }
};
