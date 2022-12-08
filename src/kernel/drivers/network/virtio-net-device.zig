const std = @import("std");
const ashet = @import("root");
const logger = std.log.scoped(.@"virtio-net-device");
const virtio = @import("virtio");

fn FixedPool(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();

        items: [size]T = undefined,
        maps: std.bit_set.StaticBitSet(size) = std.bit_set.StaticBitSet(size).initFull(),

        pub fn alloc(pool: *Self) ?*T {
            const index = pool.maps.findFirstSet() orelse return null;
            pool.maps.unset(index);
            return &pool.items[index];
        }

        pub fn get(pool: *Self, index: usize) *T {
            std.debug.assert(index < size);
            return &pool.items[index];
        }

        pub fn free(pool: *Self, item: *T) void {
            const index = @divExact((@ptrToInt(item) -% @ptrToInt(&pool.items[0])), @sizeOf(T));
            std.debug.assert(index < size);
            pool.maps.set(index);
        }
    };
}

const DeviceInfo = struct {
    const queue_size = 8;

    pub const vtable = ashet.network.NIC.VTable{
        .linkIsUp = linkIsUp,
        .allocPacket = allocPacket,
        .send = send,
        .fetch = fetchNic,
    };

    receiveq: virtio.queue.VirtQ(queue_size),
    transmitq: virtio.queue.VirtQ(queue_size),

    receive_buffers: FixedPool(Buffer, queue_size) = .{},
    transmit_buffers: FixedPool(Buffer, queue_size) = .{},

    const Buffer = extern struct {
        const max_mtu = 1514;

        header: virtio.network.NetHeader,
        data: [max_mtu]u8,
        length: usize,
    };

    comptime {
        std.debug.assert(@sizeOf(Buffer) >= 1526);
    }

    fn getDevice(nic: *ashet.network.NIC) *DeviceInfo {
        return @ptrCast(*DeviceInfo, @alignCast(@alignOf(DeviceInfo), nic.implementation));
    }

    fn linkIsUp(nic: *ashet.network.NIC) bool {
        _ = nic;
        return true;
    }

    fn allocPacket(nic: *ashet.network.NIC, size: usize) ?[]u8 {
        if (size > Buffer.max_mtu)
            return null;
        const dev = getDevice(nic);
        const buffer = dev.transmit_buffers.alloc() orelse return null;
        buffer.* = DeviceInfo.Buffer{
            .header = .{
                .flags = .{ .needs_csum = false, .data_valid = false, .rsc_info = false },
                .gso_type = .none,
                .hdr_len = 0,
                .gso_size = 0,
                .csum_start = 0,
                .csum_offset = 0,
                .num_buffers = 0,
            },
            .data = undefined,
            .length = size,
        };
        return &buffer.data;
    }

    fn send(nic: *ashet.network.NIC, packet: []u8) bool {
        std.debug.assert(packet.len == Buffer.max_mtu);
        const dev = getDevice(nic);
        const buffer = @fieldParentPtr(Buffer, "data", packet.ptr[0..Buffer.max_mtu]);

        logger.info("sending {} bytes...", .{buffer.length});

        dev.transmitq.pushDescriptorRaw(buffer, @sizeOf(virtio.network.NetHeader) + buffer.length, .read, true, true);
        dev.transmitq.exec();

        return true;
    }

    fn fetchNic(nic: *ashet.network.NIC) void {
        const dev = getDevice(nic);

        handleIncomingData(nic, dev) catch |err| {
            logger.err("error while receiving packets from nic {s}: {s}", .{ nic.getName(), @errorName(err) });
        };

        handleOutgoingData(nic, dev) catch |err| {
            logger.err("error while recycling packets from nic {s}: {s}", .{ nic.getName(), @errorName(err) });
        };
    }

    pub fn handleOutgoingData(nic: *ashet.network.NIC, dev: *DeviceInfo) !void {
        _ = nic;

        var count: usize = 0;
        while (dev.transmitq.singlePollUsed()) |ret| {
            const buffer = @intToPtr(*DeviceInfo.Buffer, @truncate(usize, dev.transmitq.descriptors[ret % DeviceInfo.queue_size].addr));
            dev.transmit_buffers.free(buffer);
            count += 1;
        }
        if (count > 0) {
            logger.info("recycled {} packets", .{count});
        }
    }

    pub fn handleIncomingData(nic: *ashet.network.NIC, dev: *DeviceInfo) !void {
        defer dev.receiveq.exec();
        while (dev.receiveq.singlePollUsed()) |ret| {
            const buffer = @intToPtr(*DeviceInfo.Buffer, @truncate(usize, dev.receiveq.descriptors[ret % DeviceInfo.queue_size].addr));

            if (buffer.header.num_buffers != 1) {
                @panic("large packets with more than one buffer not supported yet!");
            }

            // IMPORTANT:
            // This code must run in ANY CASE!
            // If the buffer isn't requeued, we're losing a receive buffer for this NIC,
            // and if that happens too often, the network reception is killed.
            defer {
                // round and round we go
                buffer.* = undefined;
                dev.receiveq.pushDescriptor(DeviceInfo.Buffer, buffer, .write, true, true);
            }

            const packet = try nic.allocPacket(buffer.data.len);
            errdefer nic.freePacket(packet);

            try packet.append(&buffer.data);

            logger.info("received data on nic {s}", .{nic.getName()});

            nic.receive(packet);
        }
    }
};

var nics: std.BoundedArray(ashet.network.NIC, 8) = .{};
var nic_devs: std.BoundedArray(DeviceInfo, 8) = .{};

pub fn getNICs() []ashet.network.NIC {
    return nics.slice();
}

fn initialize(regs: *volatile virtio.ControlRegs) !void {
    logger.info("initializing network device {*}", .{regs});

    const network_dev = &regs.device.network;

    const negotiated_features = try regs.negotiateFeatures(0 |
        virtio.FeatureFlags.any_layout |
        virtio.FeatureFlags.version_1 | // we want the non-legacy interface
        virtio.network.FeatureFlags.mtu | // we want to know the MTU
        virtio.network.FeatureFlags.mrg_rxbuf | // we can use merged buffers, for legacy interface compat
        // virtio.network.FeatureFlags.mac | // use custom mac
        virtio.network.FeatureFlags.status // we want to know the real up/down status
    );

    const features = while (true) {
        const prev = regs.config_generation;
        const set = network_dev.*;
        const next = regs.config_generation;
        if (prev == next)
            break set;
    };

    logger.info("network device info: mac={X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}, status={}, mtu={}, max queues={}, features:", .{
        features.mac[0],
        features.mac[1],
        features.mac[2],
        features.mac[3],
        features.mac[4],
        features.mac[5],
        features.status,
        features.mtu,
        features.max_virtqueue_pairs,
    });
    inline for (comptime std.meta.declarations(virtio.FeatureFlags)) |decl| {
        const has_feature = ((negotiated_features & @field(virtio.FeatureFlags, decl.name)) != 0);
        if (has_feature) {
            logger.info("- {s}", .{decl.name});
        }
    }
    inline for (comptime std.meta.declarations(virtio.network.FeatureFlags)) |decl| {
        const has_feature = ((negotiated_features & @field(virtio.network.FeatureFlags, decl.name)) != 0);
        if (has_feature) {
            logger.info("- {s}", .{decl.name});
        }
    }
    logger.info("legacy: {}", .{regs.version});

    const legacy = regs.isLegacy();
    if (legacy) {
        logger.info("network device is using legacy interface!", .{});
    }

    const nic = try nics.addOne();
    const dev = nic_devs.addOneAssumeCapacity();
    nic.* = ashet.network.NIC{
        .interface = .ethernet,
        .address = ashet.network.MAC.init(features.mac),
        .mtu = DeviceInfo.Buffer.max_mtu,

        .implementation = dev,
        .vtable = &DeviceInfo.vtable,
    };
    dev.* = DeviceInfo{
        .receiveq = undefined,
        .transmitq = undefined,
    };

    try dev.receiveq.init(virtio.network.receiveq(0), regs);
    try dev.transmitq.init(virtio.network.transmitq(0), regs);

    regs.status |= virtio.DeviceStatus.driver_ok;

    while (dev.receive_buffers.alloc()) |buffer| {
        buffer.* = undefined;
        dev.receiveq.pushDescriptor(DeviceInfo.Buffer, buffer, .write, true, true);
    }
    dev.receiveq.exec();
}
