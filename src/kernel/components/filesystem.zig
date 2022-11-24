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

fn translatePathForDev(target_buffer: []u8, path: []const u8, index: usize) error{PathTooLong}![:0]u8 {
    return std.fmt.bufPrintZ(target_buffer, "{d}:{s}", .{ index, path }) catch return error.PathTooLong;
}

/// Translates a path in the form of `CF0:/dir/file` into the form
/// `0:/dir/file` and maps the drive names to indices.
fn translatePath(target_buffer: []u8, path: []const u8) error{ PathTooLong, InvalidDevice }![:0]u8 {
    if (std.ascii.startsWithIgnoreCase(path, "SYS:")) {
        return translatePathForDev(target_buffer, path[4..], sys_disk_index);
    }

    for (disks) |disk, index| {
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

pub fn open(path: []const u8, access: ashet.abi.FileAccess, mode: ashet.abi.FileMode) !ashet.abi.FileHandle {
    const handle = try file_handles.alloc();
    errdefer file_handles.free(handle);
    const index = file_handles.handleToIndexUnsafe(handle);

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

    file_handles.backings[index] = try fatfs.File.open(fatfs_path, .{
        .mode = fatfs_mode,
        .access = fatfs_access,
    });
    errdefer file_handles.backings[index].close();

    return handle;
}

pub fn flush(handle: ashet.abi.FileHandle) !void {
    const index = try file_handles.resolve(handle);
    try file_handles.backings[index].sync();
}

pub const ReadError = error{InvalidFileHandle} || fatfs.File.ReadError;
pub fn read(handle: ashet.abi.FileHandle, buffer: []u8) ReadError!usize {
    const index = try file_handles.resolve(handle);
    return try file_handles.backings[index].read(buffer);
}

pub const Reader = std.io.Reader(ashet.abi.FileHandle, ReadError, read);
pub fn fileReader(handle: ashet.abi.FileHandle) Reader {
    return Reader{ .context = handle };
}

pub const WriteError = error{InvalidFileHandle} || fatfs.File.WriteError;
pub fn write(handle: ashet.abi.FileHandle, buffer: []const u8) !usize {
    const index = try file_handles.resolve(handle);
    return try file_handles.backings[index].write(buffer);
}

pub const Writer = std.io.Writer(ashet.abi.FileHandle, WriteError, write);
pub fn fileWriter(handle: ashet.abi.FileHandle) Writer {
    return Writer{ .context = handle };
}

pub fn seekTo(handle: ashet.abi.FileHandle, offset: u64) !void {
    const index = try file_handles.resolve(handle);
    const offset32 = std.math.cast(fatfs.FileSize, offset) orelse return error.OutOfBounds;
    try file_handles.backings[index].seekTo(offset32);
}

pub fn close(handle: ashet.abi.FileHandle) void {
    const index = file_handles.resolve(handle) catch {
        logger.info("close request for invalid file handle {}", .{handle});
        return;
    };
    file_handles.backings[index].close();
    file_handles.free(handle);
}

pub fn openDir(path: []const u8) !ashet.abi.DirectoryHandle {
    const handle = try directory_handles.alloc();
    errdefer directory_handles.free(handle);
    const index = directory_handles.handleToIndexUnsafe(handle);

    var path_buffer: [max_path]u8 = undefined;
    const fatfs_path = try translatePath(&path_buffer, path);

    directory_handles.backings[index] = try fatfs.Dir.open(fatfs_path);
    errdefer directory_handles.backings[index].close();

    return handle;
}

pub fn next(handle: ashet.abi.DirectoryHandle) !?ashet.abi.FileInfo {
    const index = try directory_handles.resolve(handle);

    const raw_info = try directory_handles.backings[index].next();

    return if (raw_info) |raw|
        translateFileInfo(raw)
    else
        null;
}

pub fn closeDir(handle: ashet.abi.DirectoryHandle) void {
    const index = directory_handles.resolve(handle) catch {
        logger.info("close request for invalid directory handle {}", .{handle});
        return;
    };
    directory_handles.backings[index].close();
    directory_handles.free(handle);
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
            const mem = buff[off .. off + sector_size];
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
