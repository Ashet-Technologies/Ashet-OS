const std = @import("std");
const virtio = @import("virtio.zig");

pub const FeatureFlags = struct {
    ///  Device handles packets with partial checksum. This “checksum offload” is a common feature on modern network cards.
    pub const csum: u64 = (1 << 0);

    ///  Driver handles packets with partial checksum.
    pub const guest_csum: u64 = (1 << 1);

    ///  Control channel offloads reconfiguration support.
    pub const ctrl_guest_offloads: u64 = (1 << 2);

    ///  Device maximum MTU reporting is supported. If offered by the device, device advises driver about the value of its maximum MTU. If negotiated, the driver uses mtu as the maximum MTU value.
    pub const mtu: u64 = (1 << 3);

    ///  Device has given MAC address.
    pub const mac: u64 = (1 << 5);

    ///  Driver can receive TSOv4.
    pub const guest_tso4: u64 = (1 << 7);

    ///  Driver can receive TSOv6.
    pub const guest_tso6: u64 = (1 << 8);

    ///  Driver can receive TSO with ECN.
    pub const guest_ecn: u64 = (1 << 9);

    ///  Driver can receive UFO.
    pub const guest_ufo: u64 = (1 << 10);

    ///  Device can receive TSOv4.
    pub const host_tso4: u64 = (1 << 11);

    ///  Device can receive TSOv6.
    pub const host_tso6: u64 = (1 << 12);

    ///  Device can receive TSO with ECN.
    pub const host_ecn: u64 = (1 << 13);

    ///  Device can receive UFO.
    pub const host_ufo: u64 = (1 << 14);

    ///  Driver can merge receive buffers.
    pub const mrg_rxbuf: u64 = (1 << 15);

    ///  Configuration status field is available.
    pub const status: u64 = (1 << 16);

    ///  Control channel is available.
    pub const ctrl_vq: u64 = (1 << 17);

    ///  Control channel RX mode support.
    pub const ctrl_rx: u64 = (1 << 18);

    ///  Control channel VLAN filtering.
    pub const ctrl_vlan: u64 = (1 << 19);

    ///  Driver can send gratuitous packets.
    pub const guest_announce: u64 = (1 << 21);

    ///  Device supports multiqueue with automatic receive steering.
    pub const mq: u64 = (1 << 22);

    ///  Set MAC address through control channel.
    pub const ctrl_mac_addr: u64 = (1 << 23);

    ///  Device can process duplicated ACKs and report number of coalesced seg-ments and duplicated ACKs
    pub const rsc_ext: u64 = (1 << 61);

    ///  Device may act as a standby for a primary device with the same MACaddress.
    pub const standby: u64 = (1 << 62);
};

pub const Config = extern struct {
    mac: [6]u8,
    status: Status,
    max_virtqueue_pairs: u16,
    mtu: u16,

    pub const Status = packed struct(u16) {
        link_up: bool,
        announce: bool,
        padding: u14 = 0,
    };
};

pub fn receiveq(index: u16) u16 {
    return 2 * index + 0;
}
pub fn transmitq(index: u16) u16 {
    return 2 * index + 1;
}
pub fn controlq(virtq_count: u16) u16 {
    return 2 * virtq_count;
}

pub const NetHeader = extern struct {
    pub const Flags = packed struct(u8) {
        needs_csum: bool, // = 1
        data_valid: bool, // = 2
        rsc_info: bool, // = 4
        padding: u5 = 0,
    };
    pub const Type = enum(u8) {
        none = 0,
        tcpv4 = 1,
        udp = 3,
        tcpv6 = 4,
        ecn = 0x80,
        _,
    };

    flags: Flags,
    gso_type: Type,
    hdr_len: u16,
    gso_size: u16,
    csum_start: u16,
    csum_offset: u16,
    num_buffers: u16,
};

comptime {
    std.debug.assert(@sizeOf(NetHeader) == 12);
}
