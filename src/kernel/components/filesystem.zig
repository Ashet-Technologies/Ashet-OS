const std = @import("std");
const fatfs = @import("fatfs");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.filesystem);

const storage = ashet.storage;

const max_path = ashet.abi.max_path;
const max_drives = fatfs.volume_count; // CF0, USB0 … USB3, ???
const max_open_files = 64;

var disks = [1]Disk{Disk{}} ** max_drives;
var filesystems: [max_drives]fatfs.FileSystem = undefined;

pub fn initialize() void {
    var index: usize = 0;
    var devices = storage.enumerate();
    while (devices.next()) |dev| : (index += 1) {
        if (index >= max_drives) {
            logger.err("detected more than {} potential drives!", .{max_drives});
            break;
        }

        logger.info("device {d}: {s}, present={}, block count={}, size={}", .{
            index,
            dev.name,
            dev.isPresent(),
            dev.blockCount(),
            std.fmt.fmtIntSizeBin(dev.byteSize()),
        });

        disks[index].blockdev = dev;
        fatfs.disks[0] = &disks[index].interface;

        if (dev.isPresent()) {
            initFileSystem(index) catch |err| {
                logger.err("failed to initialize file system {}: {s}", .{
                    index,
                    @errorName(err),
                });
            };
        }
    }

    // defer fatfs.FileSystem.unmount("0:") catch |e| std.log.err("failed to unmount filesystem: {s}", .{@errorName(e)});
}

fn initFileSystem(index: usize) !void {
    var name_buf: [4]u8 = undefined;
    const name = std.fmt.bufPrintZ(&name_buf, "{d}:", .{index}) catch @panic("name buffer too small");

    try filesystems[index].mount(name, true);

    logger.info("disk {s}: ready.", .{disks[index].blockdev.?.name});
}

/// Translates a path in the form of `CF0:/dir/file` into the form
/// `0:/dir/file` and maps the drive names to indices.
fn translatePath(target_buffer: []u8, path: []const u8) error{ PathTooLong, InvalidDevice }![:0]u8 {
    for (disks) |disk, index| {
        if (disk.blockdev) |dev| {
            var named_prefix_buf: [16]u8 = undefined;
            const named_prefix = std.fmt.bufPrint(&named_prefix_buf, "{s}:", .{dev.name}) catch @panic("disk prefix too long!");

            if (std.ascii.startsWithIgnoreCase(path, named_prefix)) {
                return std.fmt.bufPrintZ(target_buffer, "{d}:{s}", .{
                    index, path[named_prefix.len..],
                }) catch return error.PathTooLong;
            }
        }
    }
    return error.InvalidDevice;
}

pub fn stat(path: []const u8) !ashet.abi.FileInfo {
    var path_buffer: [max_path]u8 = undefined;
    const fatfs_path = try translatePath(&path_buffer, path);

    const src_stat = try fatfs.stat(fatfs_path);

    var info = ashet.abi.FileInfo{
        .name = undefined,
        .size = src_stat.fsize,
        .attributes = .{
            .directory = (src_stat.fattrib & fatfs.Attributes.directory) != 0,
            .read_only = (src_stat.fattrib & fatfs.Attributes.read_only) != 0,
            .hidden = (src_stat.fattrib & fatfs.Attributes.hidden) != 0,
        },
    };

    const src_name = std.mem.sliceTo(&src_stat.fname, 0);

    if (src_name.len > max_path)
        @panic("source file name too long!");

    std.mem.set(u8, &info.name, 0);
    std.mem.copy(u8, &info.name, src_name);

    return info;
    //
}

pub fn open(path: []const u8, access: ashet.abi.FileAccess, mode: ashet.abi.FileMode) !ashet.abi.FileHandle {
    const handle = try allocFileHandle();
    const index = handleToIndexUnsafe(handle);

    const fatfs_access = switch (access) {
        .read_only => fatfs.File.Access.read_only,
        .write_only => fatfs.File.Access.write_only,
        .read_write => fatfs.File.Access.read_write,
    };
    const fatfs_mode = switch (mode) {
        .open_existing => fatfs.File.Mode.open_existing,
        .create_new => fatfs.File.Mode.create_new,
        .create_always => fatfs.File.Mode.create_always,
        .open_always => fatfs.File.Mode.open_always,
        .open_append => fatfs.File.Mode.open_append,
    };

    var path_buffer: [max_path]u8 = undefined;
    const fatfs_path = try translatePath(&path_buffer, path);

    file_handle_backing[index] = try fatfs.File.open(fatfs_path, .{
        .mode = fatfs_mode,
        .access = fatfs_access,
    });
    errdefer file_handle_backing[index].close();

    return handle;
}

pub fn flush(handle: ashet.abi.FileHandle) !void {
    const index = try resolveHandle(handle);
    try file_handle_backing[index].sync();
}

pub fn read(handle: ashet.abi.FileHandle, buffer: []u8) !usize {
    const index = try resolveHandle(handle);
    return try file_handle_backing[index].read(buffer);
}

pub fn write(handle: ashet.abi.FileHandle, buffer: []const u8) !usize {
    const index = try resolveHandle(handle);
    return try file_handle_backing[index].write(buffer);
}

pub fn seekTo(handle: ashet.abi.FileHandle, offset: u64) !void {
    const index = try resolveHandle(handle);
    const offset32 = std.math.cast(fatfs.FileSize, offset) orelse return error.OutOfBounds;
    try file_handle_backing[index].seekTo(offset32);
}

pub fn close(handle: ashet.abi.FileHandle) void {
    const index = resolveHandle(handle) catch {
        logger.info("close request for invalid file handle {}", .{handle});
        return;
    };
    file_handle_backing[index].close();
    freeFileHandle(handle);
}

const FileHandleType = std.meta.Tag(ashet.abi.FileHandle);
const FileHandleSet = std.bit_set.ArrayBitSet(u32, max_open_files);

comptime {
    if (!std.math.isPowerOfTwo(max_open_files))
        @compileError("max_open_files must be a power of two!");
}

const file_handle_index_mask = max_open_files - 1;

var file_handle_generations = std.mem.zeroes([max_open_files]FileHandleType);
var active_file_handles = FileHandleSet.initFull();
var file_handle_backing: [max_open_files]fatfs.File = undefined;

fn allocFileHandle() error{SystemFdQuotaExceeded}!ashet.abi.FileHandle {
    if (active_file_handles.toggleFirstSet()) |index| {
        while (true) {
            const generation = file_handle_generations[index];
            const numeric = generation *% max_open_files + index;

            const handle = @intToEnum(ashet.abi.FileHandle, numeric);
            if (handle == .invalid) {
                file_handle_generations[index] += 1;
                continue;
            }
            return handle;
        }
    } else {
        return error.SystemFdQuotaExceeded;
    }
}

fn resolveHandle(handle: ashet.abi.FileHandle) !usize {
    const numeric = @enumToInt(handle);

    const index = numeric & file_handle_index_mask;
    const generation = numeric / max_open_files;

    if (file_handle_generations[index] != generation)
        return error.InvalidFileHandle;

    return index;
}

fn handleToIndexUnsafe(handle: ashet.abi.FileHandle) usize {
    const numeric = @enumToInt(handle);
    return @as(usize, numeric & file_handle_index_mask);
}

fn freeFileHandle(handle: ashet.abi.FileHandle) void {
    const numeric = @enumToInt(handle);

    const index = numeric & file_handle_index_mask;
    const generation = numeric / max_open_files;

    if (file_handle_generations[index] != generation) {
        logger.err("freeFileHandle received invalid file handle: {}(index:{}, gen:{})", .{
            numeric,
            index,
            generation,
        });
    } else {
        active_file_handles.set(index);
        file_handle_generations[index] += 1;
    }
}

const Disk = struct {
    const sector_size = 512;

    interface: fatfs.Disk = fatfs.Disk{
        .getStatusFn = getStatus,
        .initializeFn = initializeDisk,
        .readFn = readDisk,
        .writeFn = writeDisk,
        .ioctlFn = ioctl,
    },
    blockdev: ?storage.BlockDevice = null,

    fn getStatus(interface: *fatfs.Disk) fatfs.Disk.Status {
        const self = @fieldParentPtr(Disk, "interface", interface);
        return fatfs.Disk.Status{
            .initialized = (self.blockdev != null),
            .disk_present = if (self.blockdev) |dev| dev.isPresent() else false,
            .write_protected = false,
        };
    }

    fn initializeDisk(interface: *fatfs.Disk) fatfs.Disk.Error!fatfs.Disk.Status {
        const self = @fieldParentPtr(Disk, "interface", interface);

        return self.interface.getStatus();
    }

    fn readDisk(interface: *fatfs.Disk, buff: [*]u8, sector: fatfs.LBA, count: c_uint) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(Disk, "interface", interface);

        logger.info("read({*}, {}, {})", .{ buff, sector, count });

        var dev = self.blockdev orelse return error.IoError;

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const off = i * sector_size;
            const mem = @alignCast(4, buff[off .. off + sector_size]);
            dev.readBlock(sector + i, mem) catch return error.IoError;
        }
    }

    fn writeDisk(interface: *fatfs.Disk, buff: [*]const u8, sector: fatfs.LBA, count: c_uint) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(Disk, "interface", interface);

        logger.info("write({*}, {}, {})", .{ buff, sector, count });

        var dev = self.blockdev orelse return error.IoError;

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const off = (sector + i) * sector_size;
            const mem = @alignCast(4, buff[off .. off + sector_size]);
            dev.writeBlock(sector + i, mem) catch return error.IoError;
        }
    }

    fn ioctl(interface: *fatfs.Disk, cmd: fatfs.IoCtl, buff: [*]u8) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(Disk, "interface", interface);
        if (self.blockdev) |dev| {
            _ = buff;
            _ = dev;
            switch (cmd) {
                .sync => {
                    //
                },

                else => return error.InvalidParameter,
            }
        } else {
            return error.DiskNotReady;
        }
    }
};
