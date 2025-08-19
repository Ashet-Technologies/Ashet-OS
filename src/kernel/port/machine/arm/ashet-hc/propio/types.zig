const std = @import("std");

pub const FrameType = enum(u8) {
    nop = 0,
    write_fifo = 1,
    write_ram = 2,
    start_module = 3,
    stop_module = 4,
    set_leds = 5,
};

pub const ModuleID = enum(u3) {
    slot1 = 1,
    slot2 = 2,
    slot3 = 3,
    slot4 = 4,
    slot5 = 5,
    slot6 = 6,
    slot7 = 7,

    pub fn get_code_address(mid: ModuleID) u24 {
        return @as(u24, @intFromEnum(mid)) << 12;
    }

    pub fn get_conf_address(mid: ModuleID) u24 {
        return mid.get_code_address() | 0x0800;
    }

    pub fn get_ram_address(mid: ModuleID) u24 {
        return @as(u24, @intFromEnum(mid)) << 16;
    }
};

pub const FifoId = enum(u3) {
    tx_fifo0 = 0,
    tx_fifo1 = 1,
    tx_fifo2 = 2,
    tx_fifo3 = 3,

    rx_fifo0 = 4,
    rx_fifo1 = 5,
    rx_fifo2 = 6,
    rx_fifo3 = 7,

    pub fn get_config_offset(fifo: FifoId) u24 {
        return @as(u24, 8) * @intFromEnum(fifo);
    }
};

pub const FifoConfig = struct {
    base: u16,
    wptr: u8 = 0,
    rptr: u8 = 0,
    limit: u16,
};

pub const Module = struct {
    code: []const u8,
    config: struct {
        tx_fifo0: ?FifoConfig = null,
        tx_fifo1: ?FifoConfig = null,
        tx_fifo2: ?FifoConfig = null,
        tx_fifo3: ?FifoConfig = null,

        rx_fifo0: ?FifoConfig = null,
        rx_fifo1: ?FifoConfig = null,
        rx_fifo2: ?FifoConfig = null,
        rx_fifo3: ?FifoConfig = null,

        pub fn get_fifo_config(cfg: @This(), fifo: FifoId) ?FifoConfig {
            return switch (fifo) {
                inline else => |tag| @field(cfg, @tagName(tag)),
            };
        }
    },
};
