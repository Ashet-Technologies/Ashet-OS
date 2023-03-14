const std = @import("std");
const fatfs = @import("fatfs");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.filesystem);

const storage = ashet.storage;

const max_path = ashet.abi.max_path;
const max_drives = fatfs.volume_count; // CF0, USB0 … USB3, ???
const max_open_files = 64;

var sys_disk_index: u32 = 0; // system disk index for disk named SYS:

var disks = [1]Disk{Disk{}} ** max_drives;
var filesystems: [max_drives]fatfs.FileSystem = undefined;

pub fn initialize() void {
    var index: usize = 0;
    var devices = storage.enumerate();
    while (devices.next()) |dev| {
        if (index >= max_drives) {
            logger.err("detected more than {} potential drives!", .{max_drives});
            break;
        }

        if (!dev.isPresent()) {
            logger.info("device {s} not present, skipping", .{dev.name});
            continue;
        }

        logger.info("device {s}: block count={}, size={}", .{
            dev.name,
            dev.blockCount(),
            std.fmt.fmtIntSizeBin(dev.byteSize()),
        });

        disks[index].blockdev = dev;
        fatfs.disks[0] = &disks[index].interface;

        initFileSystem(index) catch |err| {
            logger.err("failed to initialize file system on disk {s}: {s}", .{
                dev.name,
                @errorName(err),
            });
            continue;
        };

        if (index == 0) {
            logger.info("SYS: is mapped to {s}:", .{dev.name});
        }

        index += 1;
    }

    // defer fatfs.FileSystem.unmount("0:") catch |e| std.log.err("failed to unmount filesystem: {s}", .{@errorName(e)});
}

fn initFileSystem(index: usize) !void {
    var name_buf: [4]u8 = undefined;
    const name = std.fmt.bufPrintZ(&name_buf, "{d}:", .{index}) catch @panic("name buffer too small");

    try filesystems[index].mount(name, true);

    logger.info("disk {s}: ready.", .{disks[index].blockdev.?.name});
}

fn translatePathForDev(target_buffer: []u8, path: []const u8, index: usize) error{PathTooLong}![:0]u8 {
    return std.fmt.bufPrintZ(target_buffer, "{d}:{s}", .{ index, path }) catch return error.PathTooLong;
}

/// Translates a path in the form of `CF0:/dir/file` into the form
/// `0:/dir/file` and maps the drive names to indices.
fn translatePath(target_buffer: []u8, path: []const u8) error{ PathTooLong, InvalidDevice }![:0]u8 {
    if (std.ascii.startsWithIgnoreCase(path, "SYS:")) {
        return translatePathForDev(target_buffer, path[4..], sys_disk_index);
    }

    for (disks, 0..) |disk, index| {
        if (disk.blockdev) |dev| {
            var named_prefix_buf: [16]u8 = undefined;
            const named_prefix = std.fmt.bufPrint(&named_prefix_buf, "{s}:", .{dev.name}) catch @panic("disk prefix too long!");

            if (std.ascii.startsWithIgnoreCase(path, named_prefix)) {
                return translatePathForDev(target_buffer, path[named_prefix.len..], index);
            }
        }
    }

    return error.InvalidDevice;
}

fn translateFileInfo(src: fatfs.FileInfo) ashet.abi.FileInfo {
    var info = ashet.abi.FileInfo{
        .name = undefined,
        .size = src.size,
        .attributes = .{
            .directory = (src.kind == .Directory),
            .read_only = src.attributes.read_only,
            .hidden = src.attributes.hidden,
        },
    };

    const src_name = src.name();

    if (src_name.len > max_path)
        @panic("source file name too long!");

    std.mem.set(u8, &info.name, 0);
    std.mem.copy(u8, &info.name, src_name);

    return info;
}

pub fn stat(path: []const u8) !ashet.abi.FileInfo {
    var path_buffer: [max_path]u8 = undefined;
    const fatfs_path = try translatePath(&path_buffer, path);

    const src_stat = try fatfs.stat(fatfs_path);

    return translateFileInfo(src_stat);
}

pub fn open(iop: *ashet.abi.fs.file.Open) void {
    const path = iop.inputs.path_ptr[0..iop.inputs.path_len];

    const handle = file_handles.alloc() catch |err| {
        ashet.io.finalizeWithError(iop, err);
        return;
    };

    const index = file_handles.handleToIndexUnsafe(handle);

    const fatfs_access = switch (iop.inputs.access) {
        .read_only => fatfs.File.Access.read_only,
        .write_only => fatfs.File.Access.write_only,
        .read_write => fatfs.File.Access.read_write,
    };
    const fatfs_mode = switch (iop.inputs.mode) {
        .open_existing => fatfs.File.Mode.open_existing,
        .create_new => fatfs.File.Mode.create_new,
        .create_always => fatfs.File.Mode.create_always,
        .open_always => fatfs.File.Mode.open_always,
        .open_append => fatfs.File.Mode.open_append,
    };

    var path_buffer: [max_path]u8 = undefined;
    const fatfs_path = translatePath(&path_buffer, path) catch |err| {
        file_handles.free(handle);
        ashet.io.finalizeWithError(iop, err);
        return;
    };

    file_handles.backings[index] = fatfs.File.open(fatfs_path, .{
        .mode = fatfs_mode,
        .access = fatfs_access,
    }) catch |err| {
        file_handles.free(handle);
        ashet.io.finalizeWithError(iop, err);
        return;
    };
    // errdefer file_handles.backings[index].close();

    ashet.io.finalizeWithResult(iop, .{ .file = handle });
}

pub fn flush(iop: *ashet.abi.fs.file.Flush) void {
    const index = file_handles.resolve(iop.inputs.file) catch |err| {
        ashet.io.finalizeWithError(iop, err);
        return;
    };
    file_handles.backings[index].sync() catch |err| {
        ashet.io.finalizeWithError(iop, err);
        return;
    };

    ashet.io.finalizeWithResult(iop, .{});
}

pub const ReadError = error{InvalidFileHandle} || fatfs.File.ReadError;
pub fn read(iop: *ashet.abi.fs.file.Read) void {
    const index = file_handles.resolve(iop.inputs.file) catch |err| {
        ashet.io.finalizeWithError(iop, err);
        return;
    };
    const count = file_handles.backings[index].read(iop.inputs.ptr[0..iop.inputs.len]) catch |err| {
        ashet.io.finalizeWithError(iop, err);
        return;
    };
    ashet.io.finalizeWithResult(iop, .{ .count = count });
}

pub const WriteError = error{InvalidFileHandle} || fatfs.File.WriteError;
pub fn write(iop: *ashet.abi.fs.file.Write) void {
    const index = file_handles.resolve(iop.inputs.file) catch |err| {
        ashet.io.finalizeWithError(iop, err);
        return;
    };
    const count = file_handles.backings[index].write(iop.inputs.ptr[0..iop.inputs.len]) catch |err| {
        ashet.io.finalizeWithError(iop, err);
        return;
    };
    ashet.io.finalizeWithResult(iop, .{ .count = count });
}

pub fn seekTo(iop: *ashet.abi.fs.file.SeekTo) void {
    const index = file_handles.resolve(iop.inputs.file) catch |err| {
        ashet.io.finalizeWithError(iop, err);
        return;
    };

    const offset32 = std.math.cast(fatfs.FileSize, iop.inputs.offset) orelse {
        ashet.io.finalizeWithError(iop, error.OutOfBounds);
        return;
    };
    file_handles.backings[index].seekTo(offset32) catch |err| {
        ashet.io.finalizeWithError(iop, err);
        return;
    };

    ashet.io.finalizeWithResult(iop, .{});
}

pub fn close(iop: *ashet.abi.fs.file.Close) void {
    const index = file_handles.resolve(iop.inputs.file) catch |err| {
        logger.info("close request for invalid file handle {}: {s}", .{ iop.inputs.file, @errorName(err) });
        ashet.io.finalizeWithError(iop, err);
        return;
    };

    file_handles.backings[index].close();
    file_handles.free(iop.inputs.file);

    ashet.io.finalizeWithResult(iop, .{});
}

pub fn openDir(iop: *ashet.abi.fs.dir.Open) void {
    const path: []const u8 = iop.inputs.path_ptr[0..iop.inputs.path_len];

    const handle = directory_handles.alloc() catch |err| {
        ashet.io.finalizeWithError(iop, err);
        return;
    };

    const index = directory_handles.handleToIndexUnsafe(handle);

    var path_buffer: [max_path]u8 = undefined;
    const fatfs_path = translatePath(&path_buffer, path) catch |err| {
        directory_handles.free(handle);
        ashet.io.finalizeWithError(iop, err);
        return;
    };

    directory_handles.backings[index] = fatfs.Dir.open(fatfs_path) catch |err| {
        directory_handles.free(handle);
        ashet.io.finalizeWithError(iop, err);
        return;
    };

    // errdefer directory_handles.backings[index].close();

    ashet.io.finalizeWithResult(iop, .{
        .dir = handle,
    });
}

pub fn next(iop: *ashet.abi.fs.dir.Next) void {
    const index = directory_handles.resolve(iop.inputs.dir) catch |err| {
        ashet.io.finalizeWithError(iop, err);
        return;
    };

    const raw_info = directory_handles.backings[index].next() catch |err| {
        ashet.io.finalizeWithError(iop, err);
        return;
    };

    ashet.io.finalizeWithResult(iop, .{
        .eof = (raw_info == null),
        .info = if (raw_info) |raw|
            translateFileInfo(raw)
        else
            undefined,
    });
}

pub fn closeDir(iop: *ashet.abi.fs.dir.Close) void {
    const index = directory_handles.resolve(iop.inputs.dir) catch |err| {
        logger.info("close request for invalid directory handle {}", .{iop.inputs.dir});
        ashet.io.finalizeWithError(iop, err);
        return;
    };
    directory_handles.backings[index].close();
    directory_handles.free(iop.inputs.dir);

    ashet.io.finalizeWithResult(iop, .{});
}

const file_handles = HandleAllocator(ashet.abi.FileHandle, fatfs.File);
const directory_handles = HandleAllocator(ashet.abi.DirectoryHandle, fatfs.Dir);

fn HandleAllocator(comptime Handle: type, comptime Backing: type) type {
    return struct {
        const HandleType = std.meta.Tag(Handle);
        const HandleSet = std.bit_set.ArrayBitSet(u32, max_open_files);

        comptime {
            if (!std.math.isPowerOfTwo(max_open_files))
                @compileError("max_open_files must be a power of two!");
        }

        const handle_index_mask = max_open_files - 1;

        var generations = std.mem.zeroes([max_open_files]HandleType);
        var active_handles = HandleSet.initFull();
        var backings: [max_open_files]Backing = undefined;

        fn alloc() error{SystemFdQuotaExceeded}!Handle {
            if (active_handles.toggleFirstSet()) |index| {
                while (true) {
                    const generation = generations[index];
                    const numeric = generation *% max_open_files + index;

                    const handle = @intToEnum(Handle, numeric);
                    if (handle == .invalid) {
                        generations[index] += 1;
                        continue;
                    }
                    return handle;
                }
            } else {
                return error.SystemFdQuotaExceeded;
            }
        }

        fn resolve(handle: Handle) !usize {
            const numeric = @enumToInt(handle);

            const index = numeric & handle_index_mask;
            const generation = numeric / max_open_files;

            if (generations[index] != generation)
                return error.InvalidFileHandle;

            return index;
        }

        fn handleToIndexUnsafe(handle: Handle) usize {
            const numeric = @enumToInt(handle);
            return @as(usize, numeric & handle_index_mask);
        }

        fn free(handle: Handle) void {
            const numeric = @enumToInt(handle);

            const index = numeric & handle_index_mask;
            const generation = numeric / max_open_files;

            if (generations[index] != generation) {
                logger.err("freeFileHandle received invalid file handle: {}(index:{}, gen:{})", .{
                    numeric,
                    index,
                    generation,
                });
            } else {
                active_handles.set(index);
                generations[index] += 1;
            }
        }
    };
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
    blockdev: ?*storage.BlockDevice = null,

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

        // logger.info("read({*}, {}, {}, {?*})", .{ buff, sector, count, self.blockdev });

        var dev = self.blockdev orelse return error.DiskNotReady;

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const off = i * sector_size;
            const mem = buff[off .. off + sector_size];
            dev.readBlock(sector + i, mem) catch return error.IoError;

            // logger.debug("{}", .{std.fmt.fmtSliceHexUpper(mem)});
        }
    }

    fn writeDisk(interface: *fatfs.Disk, buff: [*]const u8, sector: fatfs.LBA, count: c_uint) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(Disk, "interface", interface);

        // logger.info("write({*}, {}, {}, {?*})", .{ buff, sector, count, self.blockdev });

        var dev = self.blockdev orelse return error.DiskNotReady;

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const off = (sector + i) * sector_size;
            const mem = buff[off .. off + sector_size];
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

// const syscalls = struct {
//     fn @"fs.delete"(path_ptr: [*]const u8, path_len: usize) callconv(.C) abi.FileSystemError.Enum {
//         _ = path_len;
//         _ = path_ptr;
//         std.log.err("fs.delete not implemented yet!", .{});
//         return .ok;
//     }

//     fn @"fs.mkdir"(path_ptr: [*]const u8, path_len: usize) callconv(.C) abi.FileSystemError.Enum {
//         _ = path_len;
//         _ = path_ptr;
//         std.log.err("fs.mkdir not implemented yet!", .{});
//         return .ok;
//     }

//     fn @"fs.rename"(old_path_ptr: [*]const u8, old_path_len: usize, new_path_ptr: [*]const u8, new_path_len: usize) callconv(.C) abi.FileSystemError.Enum {
//         _ = old_path_len;
//         _ = old_path_ptr;
//         _ = new_path_len;
//         _ = new_path_ptr;
//         std.log.err("fs.rename not implemented yet!", .{});
//         return .ok;
//     }

//     fn @"fs.stat"(path_ptr: [*]const u8, path_len: usize, info: *abi.FileInfo) callconv(.C) abi.FileSystemError.Enum {
//         info.* = ashet.filesystem.stat(path_ptr[0..path_len]) catch |e| return abi.FileSystemError.map(e);
//         return .ok;
//     }
