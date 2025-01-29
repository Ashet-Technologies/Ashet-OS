const std = @import("std");
const ashet = @import("root");

pub const queue = @import("queue.zig");
pub const gpu = @import("gpu.zig");
pub const input = @import("input.zig");
pub const network = @import("network.zig");
pub const block = @import("block.zig");

pub const ControlRegs = extern struct {
    pub const magic: u32 = @bitCast(@as([4]u8, "virt".*));

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
        gpu: gpu.Config,
        input: input.Config,
        network: network.Config,
        block: block.Config,
    };

    pub fn isLegacy(regs: *volatile ControlRegs) bool {
        if (regs.version < 2)
            return true;

        var features: FeatureSet = .empty;

        regs.device_features_sel = 0;
        features.set_low_bits(regs.device_features);
        regs.device_features_sel = 1;
        features.set_high_bits(regs.device_features);

        return !features.contains(.version_1);
    }

    pub fn negotiateFeatures(regs: *volatile ControlRegs, requested_features: FeatureSet) !FeatureSet {
        // this sequence must be done exactly like this:
        regs.status = DeviceStatus.reset;
        regs.status |= DeviceStatus.acknowledge;
        regs.status |= DeviceStatus.driver;

        var offered_features: FeatureSet = .empty;

        regs.device_features_sel = 0;
        offered_features.set_low_bits(regs.device_features);
        regs.device_features_sel = 1;
        offered_features.set_high_bits(regs.device_features);

        const selected_features = offered_features.intersect_with(requested_features);

        const legacy = regs.isLegacy();

        regs.driver_features_sel = 0;
        regs.driver_features = selected_features.get_low_bits();

        if (!legacy) {
            regs.driver_features_sel = 1;
            regs.driver_features = selected_features.get_high_bits();
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

pub const FeatureSet = enum(u64) {
    empty = 0,

    default = FeatureFlag.version_1.mask() | FeatureFlag.any_layout.mask(),

    _,

    pub fn add(set: FeatureSet, flag: FeatureFlag) FeatureSet {
        return @enumFromInt(
            @intFromEnum(set) | flag.mask(),
        );
    }

    pub fn remove(set: FeatureSet, flag: FeatureFlag) FeatureSet {
        return @enumFromInt(
            @intFromEnum(set) & ~flag.mask(),
        );
    }

    pub fn intersect_with(lhs: FeatureSet, rhs: FeatureSet) FeatureSet {
        return @enumFromInt(
            @intFromEnum(lhs) & @intFromEnum(rhs),
        );
    }

    pub fn union_with(lhs: FeatureSet, rhs: FeatureSet) FeatureSet {
        return @enumFromInt(
            @intFromEnum(lhs) | @intFromEnum(rhs),
        );
    }

    /// Returns `true` if `set` contains `flag`.
    pub fn contains(set: FeatureSet, flag: FeatureFlag) bool {
        return (@intFromEnum(set) & flag.mask()) != 0;
    }

    /// Replaces the lower 32 bit of the feature set with `low`.
    pub fn set_low_bits(set: *FeatureSet, low: u32) void {
        var value = @intFromEnum(set.*);
        value &= 0xFFFFFFFF_00000000;
        value |= low;
        set.* = @enumFromInt(value);
    }

    /// Replaces the upper 32 bit of the feature set with `high`.
    pub fn set_high_bits(set: *FeatureSet, high: u32) void {
        var value = @intFromEnum(set.*);
        value &= 0x00000000_FFFFFFFF;
        value |= @as(u64, high) << 32;
        set.* = @enumFromInt(value);
    }

    pub fn get_low_bits(set: FeatureSet) u32 {
        return @truncate(@intFromEnum(set) >> 0);
    }

    pub fn get_high_bits(set: FeatureSet) u32 {
        return @truncate(@intFromEnum(set) >> 32);
    }
};

pub const FeatureFlag = enum(u6) {
    notify_on_empty = 24,
    any_layout = 27,
    ring_indirect_layout = 28,
    ring_event_idx = 29,
    version_1 = 32,

    _,

    pub fn new(value: u6) FeatureFlag {
        return @enumFromInt(value);
    }

    pub inline fn mask(flag: FeatureFlag) u64 {
        return @as(u64, 1) << @intFromEnum(flag);
    }
};
