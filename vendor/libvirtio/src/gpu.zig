const std = @import("std");
const virtio = @import("virtio.zig");

pub const Config = extern struct {
    events_read: u32,
    events_clear: u32,
    num_scanouts: u32,
    num_capsets: u32,
};

pub const cmd = struct {
    pub const get_display_info = 256;
    pub const resource_create_2d = 257;
    pub const resource_unref = 258;
    pub const set_scanout = 259;
    pub const resource_flush = 260;
    pub const transfer_to_host_2d = 261;
    pub const resource_attach_backing = 262;
    pub const resource_detach_backing = 263;
    pub const get_capset_info = 264;
    pub const get_capset = 265;
    pub const ctx_create = 512;
    pub const ctx_destroy = 513;
    pub const ctx_attach_resource = 514;
    pub const ctx_detach_resource = 515;
    pub const resource_create_3d = 516;
    pub const transfer_to_host_3d = 517;
    pub const transfer_from_host_3d = 518;
    pub const submit_3d = 519;
    pub const update_cursor = 768;
    pub const move_cursor = 769;
};
pub const resp = struct {
    pub const ok_nodata = 4352;
    pub const ok_display_info = 4353;
    pub const ok_capset_info = 4354;
    pub const ok_capset = 4355;
    pub const err_unspec = 4608;
    pub const err_out_of_memory = 4609;
    pub const err_invalid_scanout_id = 4610;
    pub const err_invalid_resource_id = 4611;
    pub const err_invalid_context_id = 4612;
    pub const err_invalid_parameter = 4613;
};

pub const Format = enum(u32) {
    b8g8r8a8_unorm = 1,
    b8g8r8x8_unorm = 2,
    a8r8g8b8_unorm = 3,
    x8r8g8b8_unorm = 4,
    r8g8b8a8_unorm = 67,
    x8b8g8r8_unorm = 68,
    a8b8g8r8_unorm = 121,
    r8g8b8x8_unorm = 134,
    _,
};

pub const Rect = extern struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
};

pub const CursorPos = extern struct {
    scanout_id: u32,
    x: u32,
    y: u32,
    padding: u32 = 0,
};

pub const CtrlHdr = extern struct {
    type: u32,
    flags: u32 = 0,
    fence_id: u64 = 0,
    ctx_id: u32 = 0,
    padding: u32 = 0,
};

pub const ResourceCreate2D = extern struct {
    hdr: CtrlHdr = .{ .type = cmd.resource_create_2d },
    resource_id: u32,
    format: Format,
    width: u32,
    height: u32,
};

pub const MemEntry = extern struct {
    addr: u64,
    length: u32,
    padding: u32 = 0,
};

pub const ResourceAttachBacking = extern struct {
    hdr: CtrlHdr = .{ .type = cmd.resource_attach_backing },
    resource_id: u32,
    nr_entries: u32,
    pub fn entries(self: anytype) @import("std").zig.c_translation.FlexibleArrayType(@TypeOf(self), MemEntry) {
        const Intermediate = @import("std").zig.c_translation.FlexibleArrayType(@TypeOf(self), u8);
        const ReturnType = @import("std").zig.c_translation.FlexibleArrayType(@TypeOf(self), MemEntry);
        return @as(ReturnType, @ptrCast(@alignCast(@as(Intermediate, @ptrCast(self)) + 32)));
    }
};

pub const SetScanout = extern struct {
    hdr: CtrlHdr = .{ .type = cmd.set_scanout },
    r: Rect,
    scanout_id: u32,
    resource_id: u32,
};

pub const ResourceFlush = extern struct {
    hdr: CtrlHdr = .{ .type = cmd.resource_flush },
    r: Rect,
    resource_id: u32,
    padding: u32 = 0,
};

pub const TransferToHost2D = extern struct {
    hdr: CtrlHdr = .{ .type = cmd.transfer_to_host_2d },
    r: Rect,
    offset: u64,
    resource_id: u32,
    padding: u32 = 0,
};

const PMode = extern struct {
    r: Rect,
    enabled: u32,
    flags: u32,
};

pub const DisplayInfo = extern struct {
    hdr: CtrlHdr,
    pmodes: [16]PMode,
};

pub const GPUCommand = extern union {
    hdr: CtrlHdr,
    res_create_2d: ResourceCreate2D,
    res_attach_backing: ResourceAttachBacking,
    set_scanout: SetScanout,
    res_flush: ResourceFlush,
    transfer_to_host_2d: TransferToHost2D,
};

pub const CursorCommand = extern struct {
    hdr: CtrlHdr,
    pos: CursorPos,
    resource_id: u32,
    hot_x: u32,
    hot_y: u32,
    padding: u32 = 0,
};

pub const Response = extern union {
    hdr: CtrlHdr,
    display_info: DisplayInfo,
};

pub const VIRTIO_GPU_MAX_SCANOUTS = 16;
