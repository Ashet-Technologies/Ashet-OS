//!
//! A very simple block device implemented by the Ashet OS Emulator.
//!
const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.ashet_blockdev);
const machine = ashet.machine.peripherals;

const Driver = ashet.drivers.Driver;
const BlockDevice = ashet.drivers.BlockDevice;

const Ashet_Block_Dev = @This();

pub const block_size = 512;

pub const Block = [block_size]u8;

driver: Driver,
peri: *volatile machine.BlockDevice,

pub fn init(peri: *volatile machine.BlockDevice, name: []const u8) Ashet_Block_Dev {
    return .{
        .driver = .{
            .name = "Ashet Block Device",
            .class = .{
                .block = .{
                    .name = name,
                    .block_size = block_size,
                    .num_blocks = 0,
                    .presentFn = isPresent,
                    .readFn = read,
                    .writeFn = write,
                },
            },
        },

        .peri = peri,
    };
}

pub fn isPresent(dri: *Driver) bool {
    const disk: *Ashet_Block_Dev = @alignCast(@fieldParentPtr("driver", dri));

    const status = disk.peri.status;

    disk.driver.class.block.num_blocks = if (status.present)
        disk.peri.size
    else
        0;

    return status.present;
}

pub fn read(dri: *Driver, block_num: u64, buffer: []u8) BlockDevice.ReadError!void {
    const disk: *Ashet_Block_Dev = @alignCast(@fieldParentPtr("driver", dri));

    var status = disk.peri.status;

    if (!status.present)
        return error.DeviceNotPresent;

    if (status.@"error") {
        disk.peri.command = .clear_error;
        status = disk.peri.status;
    }

    std.debug.assert(!status.busy);
    std.debug.assert(!status.@"error");

    if (block_num >= disk.peri.size)
        return error.InvalidBlock;

    disk.peri.lba = @intCast(block_num);

    disk.peri.command = .read;

    while (true) {
        status = disk.peri.status;
        // TODO: Implement timeout checking
        if (status.@"error" == true)
            break;
        if (status.busy == false)
            break;
    }

    if (status.@"error") {
        disk.peri.command = .clear_error;
        return error.Fault;
    }
    std.debug.assert(!status.busy);

    @memcpy(buffer, &disk.peri.buffer);
}

pub fn write(dri: *Driver, block_num: u64, buffer: []const u8) BlockDevice.WriteError!void {
    const disk: *Ashet_Block_Dev = @alignCast(@fieldParentPtr("driver", dri));

    var status = disk.peri.status;

    if (!status.present)
        return error.DeviceNotPresent;

    if (status.@"error") {
        disk.peri.command = .clear_error;
        status = disk.peri.status;
    }

    std.debug.assert(!status.busy);
    std.debug.assert(!status.@"error");

    if (block_num >= disk.peri.size)
        return error.InvalidBlock;

    disk.peri.lba = @intCast(block_num);

    @memcpy(&disk.peri.buffer, buffer);

    disk.peri.command = .write;

    while (true) {
        status = disk.peri.status;
        // TODO: Implement timeout checking
        if (status.@"error" == true)
            break;
        if (status.busy == false)
            break;
    }

    if (status.@"error") {
        disk.peri.command = .clear_error;
        return error.Fault;
    }
    std.debug.assert(!status.busy);
}
