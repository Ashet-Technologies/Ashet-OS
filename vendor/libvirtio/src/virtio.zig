const std = @import("std");
const ashet = @import("root");

pub const queue = @import("queue.zig");
pub const gpu = @import("gpu.zig");
pub const input = @import("input.zig");
pub const network = @import("network.zig");

pub const ControlRegs = extern struct {
    pub const magic = @bitCast(u32, @as([4]u8, "virt".*));

    magic: u32, // "virt"
    version: u32,
    device_id: DeviceId,
    vendor_id: u32,
    device_features: u32,
    device_features_sel: u32,
    reserved0: [8]u8,
    driver_features: u32,
    driver_features_sel: u32,
    legacy_guest_page_size: u32,
    reserved1: [4]u8,
    queue_sel: u32,
    queue_num_max: u32,
    queue_num: u32,
    legacy_queue_align: u32,
    legacy_queue_pfn: u32,
    queue_ready: u32,
    reserved2: [8]u8,
    queue_notify: u32,
    reserved3: [12]u8,
    interrupt_status: u32,
    interrupt_ack: u32,
    reserved4: [8]u8,
    status: u32, // DeviceStatus
    reserved5: [12]u8,
    queue_desc_lo: u32,
    queue_desc_hi: u32,
    reserved6: [8]u8,
    queue_avail_lo: u32,
    queue_avail_hi: u32,
    reserved7: [8]u8,
    queue_used_lo: u32,
    queue_used_hi: u32,
    reserved8: [8]u8,

    reserved9: [0x40]u8,

    reserved10: [12]u8,
    config_generation: u32,

    device: DeviceInfo,

    pub const DeviceInfo = extern union {
        padding: [0xf00]u8,
        gpu: gpu.Config,
        input: input.Config,
        network: network.Config,
    };

    pub fn isLegacy(regs: *volatile ControlRegs) bool {
        var features: u64 = undefined;

        regs.device_features_sel = 0;
        features = @as(u64, regs.device_features) << 0;
        regs.device_features_sel = 1;
        features |= @as(u64, regs.device_features) << 32;

        return regs.version < 2 or (features & FeatureFlags.version_1) == 0;
    }

    pub fn negotiateFeatures(regs: *volatile ControlRegs, requested_features: u64) !u64 {
        // this sequence must be done exactly like this:
        regs.status = DeviceStatus.reset;
        regs.status |= DeviceStatus.acknowledge;
        regs.status |= DeviceStatus.driver;

        var offered_features: u64 = 0;

        regs.device_features_sel = 0;
        offered_features = @as(u64, regs.device_features) << 0;
        regs.device_features_sel = 1;
        offered_features |= @as(u64, regs.device_features) << 32;

        const selected_features = offered_features & requested_features;

        const legacy = regs.isLegacy();

        regs.driver_features_sel = 0;
        regs.driver_features = @truncate(u32, selected_features >> 0);

        if (!legacy) {
            regs.driver_features_sel = 1;
            regs.driver_features = @truncate(u32, selected_features >> 32);
        }

        if (legacy) {
            regs.legacy_guest_page_size = std.mem.page_size;
        } else {
            regs.status |= DeviceStatus.features_ok;

            if ((regs.status & DeviceStatus.features_ok) == 0) {
                return error.DeviceDoesNotAcceptFeatures;
            }
        }

        return selected_features;
    }
};

pub const DeviceStatus = struct {
    pub const reset: u32 = 0;
    pub const acknowledge: u32 = 1;
    pub const driver: u32 = 2;
    pub const driver_ok: u32 = 4;
    pub const features_ok: u32 = 8;
    pub const device_needs_reset: u32 = 64;
    pub const failed: u32 = 128;
};

pub const DeviceId = enum(u32) {
    reserved = 0,
    network = 1,
    block = 2,
    console = 3,
    entropy_source = 4,
    memory_balloon_legacy = 5,
    iomemory = 6,
    rpmsg = 7,
    scsi_host = 8,
    @"9_p" = 9,
    @"80211" = 10,
    rproc_serial = 11,
    caif = 12,
    memory_balloon = 13,
    gpu = 16,
    timer = 17,
    input = 18,
    _,
};

pub const FeatureFlags = struct {
    pub const notify_on_empty: u64 = (1 << 24);
    pub const any_layout: u64 = (1 << 27);
    pub const ring_indirect_layout: u64 = (1 << 28);
    pub const ring_event_idx: u64 = (1 << 29);
    pub const version_1: u64 = (1 << 32);
};
