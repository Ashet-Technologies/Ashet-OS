const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.@"host-disk-image");

const Driver = ashet.drivers.Driver;
const BlockDevice = ashet.drivers.BlockDevice;

const Host_Disk_Image = @This();

driver: Driver,
file: std.fs.File,
mode: std.fs.File.OpenMode,

pub fn init(file: std.fs.File, mode: std.fs.File.OpenMode) !Host_Disk_Image {
    const stat = try file.stat();
    const block_size = 512;

    const block_count = stat.size / block_size;

    return .{
        .driver = .{
            .name = "Host Disk Image",
            .class = .{
                .block = .{
                    .name = "HDI",
                    .block_size = block_size,
                    .num_blocks = block_count,
                    .presentFn = isPresent,
                    .readFn = read,
                    .writeFn = write,
                },
            },
        },
        .file = file,
        .mode = mode,
    };
}

pub fn isPresent(dri: *Driver) bool {
    const disk = @fieldParentPtr(Host_Disk_Image, "driver", dri);
    _ = disk;
    return true;
}

pub fn read(dri: *Driver, block_num: u64, buffer: []u8) BlockDevice.ReadError!void {
    const disk = @fieldParentPtr(Host_Disk_Image, "driver", dri);

    const offset = 512 * block_num;
    disk.file.seekTo(offset) catch return error.Fault;
    disk.file.reader().readNoEof(buffer) catch return error.Fault;
}

pub fn write(dri: *Driver, block_num: u64, buffer: []const u8) BlockDevice.WriteError!void {
    const disk = @fieldParentPtr(Host_Disk_Image, "driver", dri);

    if (disk.mode != .read_write)
        return error.NotSupported;

    const offset = 512 * block_num;
    disk.file.seekTo(offset) catch return error.Fault;
    disk.file.writeAll(buffer) catch return error.Fault;
}
