const std = @import("std");
const ashet = @import("root");
const virtio = @import("virtio.zig");

const page_size = ashet.memory.page_size;

pub const AbsInfo = extern struct {
    min: u32,
    max: u32,
    fuzz: u32,
    flat: u32,
    res: u32,
};

pub const DevIDs = extern struct {
    bustype: u16,
    vendor: u16,
    product: u16,
    version: u16,
};

pub const Config = extern struct {
    select: ConfigSelect,
    subsel: ConfigEvSubSel,
    size: u8,
    reserved: [5]u8,
    data: Data,

    const Data = extern union {
        string: [128]u8,
        bitmap: [128]u8,
        abs: AbsInfo,
        ids: DevIDs,

        pub fn isBitSet(self: Data, bit: u16) bool {
            return self.bitmap[bit / 8] & (@as(u8, 1) << @truncate(u3, bit % 8)) != 0;
        }
    };
};

pub const ConfigSelect = enum(u8) {
    unset = 0x00,
    id_name = 0x01,
    id_serial = 0x02,
    id_devids = 0x03,
    prop_bits = 0x10,
    ev_bits = 0x11,
    abs_info = 0x12,
    _,
};

pub const ConfigEvSubSel = enum(u8) {
    unset = 0x00,
    cess_key = 0x01,
    cess_rel = 0x02,
    cess_abs = 0x03,
    _,
};

pub const Event = extern struct {
    type: u16 align(16),
    code: u16,
    value: u32,
};
