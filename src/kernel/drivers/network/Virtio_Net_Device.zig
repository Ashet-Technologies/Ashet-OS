const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.@"virtio-net");
const virtio = @import("virtio");

const Virtio_Net_Device = @This();
const Driver = ashet.drivers.Driver;

const vtable = ashet.network.NetworkInterface.VTable{
    .linkIsUpFn = linkIsUp,
    .allocOutgoingPacketFn = allocPacket,
    .sendFn = send,
    .pollFn = fetchNic,
};

driver: Driver = .{
    .name = "Virtio Net Device",
    .class = .{
        .network = .{
            .interface = .ethernet,
            .address = undefined,
            .mtu = Buffer.max_mtu,
            .vtable = &vtable,
        },
    },
},

receiveq: virtio.queue.VirtQ(queue_size) = undefined,
transmitq: virtio.queue.VirtQ(queue_size) = undefined,

receive_buffers: FixedPool(Buffer, queue_size) = .{},
transmit_buffers: FixedPool(Buffer, queue_size) = .{},

pub fn init(allocator: std.mem.Allocator, regs: *volatile virtio.ControlRegs) !*Virtio_Net_Device {
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
    const device = try allocator.create(Virtio_Net_Device);
    errdefer allocator.destroy(device);

    device.* = Virtio_Net_Device{};

    device.driver.class.network.address = ashet.network.MAC.init(features.mac);

    try device.receiveq.init(virtio.network.receiveq(0), regs);
    try device.transmitq.init(virtio.network.transmitq(0), regs);

    regs.status |= virtio.DeviceStatus.driver_ok;

    while (device.receive_buffers.alloc()) |buffer| {
        buffer.* = undefined;
        device.receiveq.pushDescriptor(Buffer, buffer, .write, true, true);
    }
    device.receiveq.exec();

    return device;
}

const queue_size = 8;

const Buffer = extern struct {
    const max_mtu = 1514;

    header: virtio.network.NetHeader,
    data: [max_mtu]u8,
    length: usize,
};

comptime {
    std.debug.assert(@sizeOf(Buffer) >= 1526);
}

fn linkIsUp(driver: *Driver) bool {
    const device = @fieldParentPtr(Virtio_Net_Device, "driver", driver);
    _ = device;
    return true;
}

fn allocPacket(driver: *Driver, size: usize) ?[]u8 {
    const device = @fieldParentPtr(Virtio_Net_Device, "driver", driver);

    if (size > Buffer.max_mtu)
        return null;
    const buffer = device.transmit_buffers.alloc() orelse return null;
    buffer.* = Buffer{
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

fn send(driver: *Driver, packet: []u8) bool {
    std.debug.assert(packet.len == Buffer.max_mtu);

    const device = @fieldParentPtr(Virtio_Net_Device, "driver", driver);

    const buffer = @fieldParentPtr(Buffer, "data", packet.ptr[0..Buffer.max_mtu]);

    logger.debug("sending {} bytes...", .{buffer.length});

    device.transmitq.pushDescriptorRaw(buffer, @sizeOf(virtio.network.NetHeader) + buffer.length, .read, true, true);
    device.transmitq.exec();

    return true;
}

fn fetchNic(driver: *Driver) void {
    const device = @fieldParentPtr(Virtio_Net_Device, "driver", driver);

    device.handleIncomingData() catch |err| {
        logger.err("error while receiving packets from nic {s}: {s}", .{ device.driver.class.network.getName(), @errorName(err) });
    };

    device.handleOutgoingData() catch |err| {
        logger.err("error while recycling packets from nic {s}: {s}", .{ device.driver.class.network.getName(), @errorName(err) });
    };
}

pub fn handleOutgoingData(device: *Virtio_Net_Device) !void {
    var count: usize = 0;
    while (device.transmitq.singlePollUsed()) |ret| {
        const buffer = @ptrFromInt(*Buffer, @truncate(usize, device.transmitq.descriptors[ret % queue_size].addr));
        device.transmit_buffers.free(buffer);
        count += 1;
    }
    if (count > 0) {
        logger.debug("recycled {} packets", .{count});
    }
}

pub fn handleIncomingData(device: *Virtio_Net_Device) !void {
    const nic = &device.driver.class.network;

    defer device.receiveq.exec();
    while (device.receiveq.singlePollUsed()) |ret| {
        const buffer = @ptrFromInt(*Buffer, @truncate(usize, device.receiveq.descriptors[ret % queue_size].addr));

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
            device.receiveq.pushDescriptor(Buffer, buffer, .write, true, true);
        }

        const packet = try nic.allocIncomingPacket(buffer.data.len);
        errdefer nic.freeIncomingPacket(packet);

        try packet.append(&buffer.data);

        logger.debug("received data on nic {s}", .{nic.getName()});

        nic.receive(packet);
    }
}

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
            const index = @divExact((@intFromPtr(item) -% @intFromPtr(&pool.items[0])), @sizeOf(T));
            std.debug.assert(index < size);
            pool.maps.set(index);
        }
    };
}
