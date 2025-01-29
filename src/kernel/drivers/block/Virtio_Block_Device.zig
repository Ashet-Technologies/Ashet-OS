const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.@"virtio-block");
const virtio = @import("virtio");

const Virtio_Block_Device = @This();
const Driver = ashet.drivers.Driver;

const ReadError = ashet.storage.BlockDevice.ReadError;
const WriteError = ashet.storage.BlockDevice.WriteError;

const queue_size = 2;
const requestq = 0;

const Request = virtio.block.FixedSizeRequest(512);

driver: Driver,

regs: *volatile virtio.ControlRegs,

// active_requests: [queue_size]Request,
vq: virtio.queue.VirtQ(queue_size),

is_legacy: bool,

pub fn init(allocator: std.mem.Allocator, regs: *volatile virtio.ControlRegs) !*Virtio_Block_Device {
    logger.info("initializing block device {*}", .{regs});

    const block_dev = &regs.device.block;

    const available_features = try regs.negotiateFeatures(virtio.FeatureSet.default
        .add(virtio.block.FeatureFlag.block_size)
        .add(virtio.block.FeatureFlag.topology)
        .add(virtio.block.FeatureFlag.geometry));

    const is_legacy = !available_features.contains(.version_1);
    if (is_legacy) {
        logger.info("block device is legacy device!", .{});
    }

    logger.debug("available block device features: 0x{X:0>8}", .{@intFromEnum(available_features)});

    logger.info("device size: {}", .{block_dev.capacity});

    if (available_features.contains(virtio.block.FeatureFlag.block_size)) {
        logger.info("optimal block size: {}", .{block_dev.block_size.read(is_legacy)});
    }
    if (available_features.contains(virtio.block.FeatureFlag.geometry)) {
        logger.info("device geometry: C={} H={} S={}", .{
            block_dev.geometry.cylinders.read(is_legacy),
            block_dev.geometry.heads,
            block_dev.geometry.sectors,
        });
    }
    if (available_features.contains(virtio.block.FeatureFlag.topology)) {
        logger.info("device topology: block_log2={} align_off={} min_io={} opt_io={}", .{
            block_dev.topology.physical_block_exp,
            block_dev.topology.alignment_offset,
            block_dev.topology.min_io_size.read(is_legacy),
            block_dev.topology.opt_io_size.read(is_legacy),
        });
    }

    const device = try allocator.create(Virtio_Block_Device);
    errdefer allocator.destroy(device);

    device.* = Virtio_Block_Device{
        .driver = .{
            .name = "Virtio Block Device",
            .class = .{
                .block = .{
                    .block_size = 512,
                    .name = "virtio",
                    .num_blocks = block_dev.capacity.read(is_legacy),
                    .presentFn = is_present,
                    .readFn = read_block,
                    .writeFn = write_block,
                },
            },
        },
        .regs = regs,
        // .requests = std.mem.zeroes([queue_size]Request),
        .vq = undefined,
        .is_legacy = is_legacy,
    };

    try device.vq.init(requestq, regs);

    regs.status |= virtio.DeviceStatus.driver_ok;

    return device;
}

fn is_present(dri: *Driver) bool {
    const device: *Virtio_Block_Device = dri.resolve(Virtio_Block_Device, "driver");
    _ = device;
    return true;
}

fn read_block(dri: *Driver, block: u64, buffer: []u8) ReadError!void {
    const device: *Virtio_Block_Device = dri.resolve(Virtio_Block_Device, "driver");

    _ = buffer;

    if (block >= device.driver.class.block.num_blocks)
        return error.InvalidBlock;

    var req = Request{
        .type = .zero,
        .reserved = .zero,
        .sector = .zero,
        .data = undefined,
        .status = .initial,
    };

    req.type.write(@intFromEnum(virtio.block.RequestType.in), device.is_legacy);
    req.sector.write(block, device.is_legacy);

    // TODO: Continue here!
    // https://docs.oasis-open.org/virtio/virtio/v1.1/virtio-v1.1.pdf

    std.log.info("req start: {}", .{req});

    device.vq.waitSettled();

    device.vq.pushDescriptor(Request, &req, .write, true, true);
    device.vq.exec();

    _ = device.vq.waitUsed();

    std.log.info("req done: {}", .{req});
}

fn write_block(dri: *Driver, block: u64, buffer: []const u8) WriteError!void {
    const device: *Virtio_Block_Device = dri.resolve(Virtio_Block_Device, "driver");

    if (block >= device.driver.class.block.num_blocks)
        return error.InvalidBlock;

    _ = buffer;

    @panic("unsupported: block writes!");
}

fn getDeviceEvent(dev: *Virtio_Block_Device) ?virtio.input.Event {
    const ret = dev.vq.singlePollUsed() orelse return null;

    const evt = dev.events[ret % queue_size];
    dev.vq.avail_i += 1;
    dev.vq.exec();

    return evt;
}
