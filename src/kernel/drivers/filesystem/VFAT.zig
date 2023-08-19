const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.vfat);
const fatfs = @import("fatfs");
const astd = @import("ashet-std");

const FileSystemDriver = ashet.drivers.FileSystemDriver;
const GenericInstance = ashet.drivers.FileSystemDriver.Instance;
const GenericEnumerator = ashet.drivers.FileSystemDriver.Enumerator;

comptime {
    // enforce module instantiation:
    _ = fatfs;
}

pub const max_path = 511;

pub const max_open_files = 64;

pub var driver = ashet.drivers.Driver{
    .name = "VFAT",
    .class = .{
        .filesystem = .{
            .createInstanceFn = createInstance,
            .destroyInstanceFn = destroyInstance,
        },
    },
};

const PathBuffer = struct {
    buffer: [max_path + 1]u8,

    pub fn init(string: []const u8) error{OutOfMemory}!PathBuffer {
        if (string.len > max_path)
            return error.OutOfMemory;
        var buf = PathBuffer{ .buffer = undefined };
        std.mem.copyForwards(u8, &buf.buffer, string);
        buf.buffer[string.len] = 0;
        return buf;
    }

    pub fn str(path: *const PathBuffer) [:0]const u8 {
        return path.buffer[0..std.mem.indexOfScalar(u8, &path.buffer, 0).? :0];
    }
};

const FileHandle = ashet.drivers.FileSystemDriver.FileHandle;
const DirectoryHandle = ashet.drivers.FileSystemDriver.DirectoryHandle;

/// AshetFS driver block device wrapper
const BlockDevice = struct {
    const BD = @This();

    const sector_size = 512;
    const logger = std.log.scoped(.disk);

    disk: fatfs.Disk = fatfs.Disk{
        .getStatusFn = getStatus,
        .initializeFn = initialize,
        .readFn = read,
        .writeFn = write,
        .ioctlFn = ioctl,
    },
    backing: *ashet.storage.BlockDevice,

    fn interface(dev: *BlockDevice) *fatfs.Disk {
        return &dev.disk;
    }

    pub fn getStatus(intf: *fatfs.Disk) fatfs.Disk.Status {
        const self = @fieldParentPtr(BlockDevice, "disk", intf);
        return fatfs.Disk.Status{
            .initialized = true,
            .disk_present = self.backing.isPresent(),
            .write_protected = false, // TODO: Maybe expose this directly from the interface?
        };
    }

    pub fn initialize(intf: *fatfs.Disk) fatfs.Disk.Error!fatfs.Disk.Status {
        const self = @fieldParentPtr(BlockDevice, "disk", intf);
        return getStatus(&self.disk);
    }

    pub fn read(intf: *fatfs.Disk, buff: [*]u8, sector: fatfs.LBA, count: c_uint) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(BlockDevice, "disk", intf);

        const block_ptr = @as([*][512]u8, @ptrCast(buff));

        var i: usize = 0;
        while (i < count) : (i += 1) {
            self.backing.readBlock(sector + i, &block_ptr[i]) catch |err| switch (err) {
                error.DeviceNotPresent => return error.DiskNotReady,
                error.Fault => return error.IoError,
                error.InvalidBlock => return error.IoError,
                error.Timeout => return error.IoError,
            };
        }
    }

    pub fn write(intf: *fatfs.Disk, buff: [*]const u8, sector: fatfs.LBA, count: c_uint) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(BlockDevice, "disk", intf);

        const block_ptr = @as([*]const [512]u8, @ptrCast(buff));

        var i: usize = 0;
        while (i < count) : (i += 1) {
            self.backing.writeBlock(sector + i, &block_ptr[i]) catch |err| switch (err) {
                error.DeviceNotPresent => return error.DiskNotReady,
                error.Fault => return error.IoError,
                error.InvalidBlock => return error.IoError,
                error.Timeout => return error.IoError,
                error.NotSupported => return error.WriteProtected,
            };
        }
    }

    pub fn ioctl(intf: *fatfs.Disk, cmd: fatfs.IoCtl, buff: [*]u8) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(BlockDevice, "disk", intf);
        switch (cmd) {
            .sync => {
                // TODO: Implement block device flushing
            },

            .get_sector_count => {
                const size: *fatfs.LBA = @ptrCast(@alignCast(buff));
                size.* = @intCast(self.backing.blockCount());
            },
            .get_sector_size => {
                const size: *fatfs.WORD = @ptrCast(@alignCast(buff));
                size.* = @intCast(self.backing.blockSize());
            },
            .get_block_size => {
                const size: *fatfs.DWORD = @ptrCast(@alignCast(buff));
                size.* = 1;
            },

            else => return error.InvalidParameter,
        }
    }
};

fn createInstance(dri: *ashet.drivers.Driver, allocator: std.mem.Allocator, block_device: *ashet.drivers.BlockDevice) ashet.drivers.FileSystemDriver.CreateError!*GenericInstance {
    const instance = try allocator.create(Instance);
    errdefer allocator.destroy(instance);

    instance.* = Instance{
        .block_device = BlockDevice{ .backing = block_device },
        .generic = .{
            .driver = dri,
            .vtable = &Instance.vtable,
        },
        .enumerator_pool = std.heap.MemoryPool(Enumerator).init(allocator),

        .disk_index = undefined,
    };
    errdefer instance.enumerator_pool.deinit();

    instance.init() catch |err| switch (err) {
        else => return error.DeviceError,
    };

    return &instance.generic;
}

fn destroyInstance(dri: *ashet.drivers.Driver, allocator: std.mem.Allocator, generic_instance: *GenericInstance) void {
    _ = dri;

    const instance = Instance.getPtr(generic_instance);

    instance.deinit();

    allocator.destroy(instance);
}

fn enumCast(comptime T: type, v: anytype) T {
    return @as(T, @enumFromInt(@intFromEnum(v)));
}

const File = struct {
    file: fatfs.File,
};

const Directory = struct {
    dir: fatfs.Dir,
    full_path: PathBuffer,
};

const Instance = struct {
    disk_index: u8,
    generic: GenericInstance,
    filesystem: fatfs.FileSystem = undefined, // requires pointer stability
    block_device: BlockDevice, // requires pointer stability
    enumerator_pool: std.heap.MemoryPool(Enumerator),

    file_handles: astd.HandleAllocator(FileSystemDriver.FileHandle, File, max_open_files) = .{},
    dir_handles: astd.HandleAllocator(FileSystemDriver.DirectoryHandle, Directory, max_open_files) = .{},

    fn init(instance: *Instance) !void {
        instance.disk_index = for (&fatfs.disks, 0..) |*disk_ptr, disk_index| {
            if (disk_ptr.* == null) {
                disk_ptr.* = instance.block_device.interface();
                break @as(u8, @intCast(disk_index));
            }
        } else return error.SystemResources;

        var path_buffer: [8]u8 = undefined;

        const path = std.fmt.bufPrintZ(&path_buffer, "{d}:", .{instance.disk_index}) catch unreachable;

        try fatfs.FileSystem.mount(&instance.filesystem, path, true);
    }

    fn deinit(instance: *Instance) void {
        instance.enumerator_pool.deinit();
        instance.* = undefined;
    }

    fn buildPath(instance: *Instance, root: []const u8, path: []const u8) error{ InvalidPath, SystemResources }!PathBuffer {
        var buf = PathBuffer{ .buffer = undefined };
        var stream = std.io.fixedBufferStream(buf.buffer[0 .. buf.buffer.len - 1]);
        {
            const writer = stream.writer();

            if (root.len > 0) {
                const index = std.mem.indexOfScalar(u8, root, ':').?;
                for (root[0..index]) |c| {
                    std.debug.assert(c >= '0' or c <= '9');
                }
                writer.print("{s}/", .{root}) catch return error.SystemResources;
            } else {
                writer.print("{d}:", .{instance.disk_index}) catch return error.SystemResources;
            }

            writer.writeAll(path) catch return error.SystemResources;
        }
        @memset(buf.buffer[stream.pos..], 0); // add NUL termination
        return buf;
    }

    fn openDirInternal(generic: *GenericInstance, base_path: []const u8, path: []const u8) !DirectoryHandle {
        const instance = getPtr(generic);

        const full_path = try instance.buildPath(base_path, path);

        const handle = try instance.dir_handles.alloc();
        errdefer instance.dir_handles.free(handle);

        var dir = fatfs.Dir.open(full_path.str()) catch |err| switch (err) {
            error.DiskErr => return error.DiskError,
            error.IntErr => @panic("unexpected error IntErr"),
            error.InvalidDrive => @panic("unexpected error InvalidDrive"),
            error.InvalidName => @panic("unexpected error InvalidName"),
            error.InvalidObject => @panic("unexpected error InvalidObject"),
            error.NoFilesystem => return error.FileNotFound,
            error.NoPath => return error.FileNotFound,
            error.NotEnabled => @panic("unexpected error NotEnabled"),
            error.NotReady => @panic("unexpected error NotReady"),
            error.OutOfMemory => return error.SystemResources,
            error.Timeout => return error.DiskError,
            error.TooManyOpenFiles => return error.SystemResources,
        };
        errdefer dir.close();

        const backing = instance.dir_handles.handleToBackingUnsafe(handle);
        backing.* = Directory{
            .full_path = full_path,
            .dir = dir,
        };

        return handle;
    }

    fn openDirFromRoot(generic: *GenericInstance, path: []const u8) FileSystemDriver.OpenDirAbsError!DirectoryHandle {
        return openDirInternal(generic, "", path);
    }

    fn openDirRelative(generic: *GenericInstance, base_dir: DirectoryHandle, path: []const u8) FileSystemDriver.OpenDirRelError!DirectoryHandle {
        const instance = getPtr(generic);

        const ctx = instance.dir_handles.resolve(base_dir) catch return error.SystemResources;

        return openDirInternal(generic, ctx.full_path.str(), path);
    }

    fn closeDir(generic: *GenericInstance, dir: DirectoryHandle) void {
        const instance = getPtr(generic);

        const backing = instance.dir_handles.resolve(dir) catch return;
        backing.dir.close();
        instance.dir_handles.free(dir);
    }

    fn openFile(generic: *GenericInstance, base_dir: DirectoryHandle, path: []const u8, access: ashet.abi.FileAccess, mode: ashet.abi.FileMode) FileSystemDriver.OpenFileError!FileHandle {
        const instance = getPtr(generic);

        const dir = try instance.dir_handles.resolve(base_dir);

        const full_path = try instance.buildPath(dir.full_path.str(), path);

        const handle = try instance.file_handles.alloc();
        errdefer instance.file_handles.free(handle);

        const open_flags = fatfs.File.OpenFlags{
            .access = switch (access) {
                .read_only => .read_only,
                .write_only => .write_only,
                .read_write => .read_write,
            },
            .mode = switch (mode) {
                .open_existing => .open_existing,
                .open_always => .open_always,
                .create_new => .create_new,
                .create_always => .create_always,
            },
        };

        var file = fatfs.File.open(full_path.str(), open_flags) catch |err| switch (err) {
            error.DiskErr => return error.DiskError,
            error.IntErr => return error.DiskError,
            error.Timeout => return error.DiskError,

            error.NoFilesystem => return error.FileNotFound,
            error.NoPath => return error.FileNotFound,
            error.NoFile => return error.FileNotFound,

            error.OutOfMemory => return error.SystemResources,
            error.TooManyOpenFiles => return error.SystemResources,

            error.Exist => return error.FileAlreadyExists,

            error.WriteProtected => return error.WriteProtected,

            error.Denied => @panic("unexpected error.Denied"),
            error.InvalidDrive => @panic("unexpected error.InvalidDrive"),
            error.InvalidName => @panic("unexpected error.InvalidName"),
            error.InvalidObject => @panic("unexpected error.InvalidObject"),
            error.Locked => @panic("unexpected error.Locked"),
            error.NotEnabled => @panic("unexpected error.NotEnabled"),
            error.NotReady => @panic("unexpected error.NotReady"),
        };
        errdefer dir.close();

        const backing = instance.file_handles.handleToBackingUnsafe(handle);
        backing.* = File{
            .file = file,
        };

        return handle;
    }

    fn closeFile(generic: *GenericInstance, dir: FileHandle) void {
        const instance = getPtr(generic);

        const file = instance.file_handles.resolve(dir) catch return;
        file.file.close();
        instance.file_handles.free(dir);
    }

    fn read(generic: *GenericInstance, file_handle: FileHandle, offset: u64, buffer: []u8) FileSystemDriver.ReadError!usize {
        const instance = getPtr(generic);

        const file = try instance.file_handles.resolve(file_handle);

        file.file.seekTo(std.math.cast(u32, offset) orelse return 0) catch |err| switch (err) {
            error.DiskErr, error.IntErr, error.Timeout => return error.DiskError,
            error.InvalidObject => @panic("unexpected error.InvalidObject"),
        };

        return file.file.read(buffer) catch |err| switch (err) {
            error.DiskErr, error.IntErr, error.Timeout => return error.DiskError,
            error.InvalidObject => @panic("unexpected error.InvalidObject"),
            error.Denied => @panic("unexpected error.Denied"),
            error.Overflow => return error.SystemResources,
        };
    }

    fn write(generic: *GenericInstance, file_handle: FileHandle, offset: u64, buffer: []const u8) FileSystemDriver.WriteError!usize {
        const instance = getPtr(generic);
        _ = instance;
        _ = file_handle;
        _ = offset;
        _ = buffer;
        @panic("write");

        // return instance.fs.writeData(enumCast(afs.FileHandle, file_handle), offset, buffer) catch |err| return try mapFileSystemError(err);
    }

    fn statFile(generic: *GenericInstance, file_handle: FileHandle) FileSystemDriver.StatFileError!ashet.abi.FileInfo {
        const instance = getPtr(generic);

        const file = try instance.file_handles.resolve(file_handle);

        return .{
            .name = nameToBuf(""),
            .size = file.file.size(),
            .attributes = .{
                .directory = false,
            },
            .creation_date = 0, // TODO: Fill out dateTimeFromTimestamp(info.date, info.time),
            .modified_date = 0, // TODO: Fill out dateTimeFromTimestamp(info.date, info.time),
        };
    }

    fn createEnumerator(generic_instance: *GenericInstance, directory_handle: DirectoryHandle) FileSystemDriver.CreateEnumeratorError!*GenericEnumerator {
        const instance = getPtr(generic_instance);

        const dir: *Directory = instance.dir_handles.resolve(directory_handle) catch @panic("invalid handle passed");

        var child_dir = fatfs.Dir.open(dir.full_path.str()) catch |err| switch (err) {
            error.DiskErr => return error.DiskError,
            error.IntErr => return error.DiskError,
            error.InvalidDrive => @panic("unexpected error: InvalidDrive"),
            error.InvalidName => @panic("unexpected error: InvalidName"),
            error.InvalidObject => @panic("unexpected error: InvalidObject"),
            error.NoFilesystem => @panic("unexpected error: NoFilesystem"),
            error.NoPath => @panic("unexpected error: NoPath"),
            error.NotEnabled => @panic("unexpected error: NotEnabled"),
            error.OutOfMemory => @panic("unexpected error: NotEnoughCore"),
            error.NotReady => @panic("unexpected error: NotReady"),
            error.Timeout => @panic("unexpected error: Timeout"),
            error.TooManyOpenFiles => return error.SystemResources,
        };
        errdefer child_dir.close();

        const enumerator = instance.enumerator_pool.create() catch return error.SystemResources;
        errdefer instance.enumerator_pool.destroy(enumerator);

        enumerator.* = Enumerator{
            .generic = .{
                .instance = generic_instance,
                .vtable = &Enumerator.vtable,
            },
            .directory = child_dir,
        };

        return &enumerator.generic;
    }

    fn destroyEnumerator(generic_instance: *GenericInstance, generic_enumerator: *GenericEnumerator) void {
        const instance = getPtr(generic_instance);
        const enumerator = Enumerator.getPtr(generic_enumerator);

        enumerator.directory.close();

        instance.enumerator_pool.destroy(enumerator);
    }

    fn getPtr(p: *GenericInstance) *Instance {
        return @fieldParentPtr(Instance, "generic", p);
    }

    const vtable = GenericInstance.VTable{
        .openDirFromRootFn = openDirFromRoot,
        .openDirRelativeFn = openDirRelative,
        .closeDirFn = closeDir,

        .deleteFn = undefined, // TODO: Fix later
        .mkdirFn = undefined, // TODO: Fix later
        .statEntryFn = undefined, // TODO: Fix later
        .nearMoveFn = undefined, // TODO: Fix later
        .farMoveFn = undefined, // TODO: Fix later
        .copyFn = undefined, // TODO: Fix later

        .createEnumeratorFn = createEnumerator,
        .destroyEnumeratorFn = destroyEnumerator,

        .openFileFn = openFile,
        .closeFileFn = closeFile,
        .readFn = read,
        .writeFn = write,
        .statFileFn = statFile,
        .resizeFn = undefined, // TODO: Fix later
        .flushFileFn = undefined, // TODO: Fix later

    };
};

const Enumerator = struct {
    generic: GenericEnumerator,
    directory: fatfs.Dir,

    fn reset(inst: *GenericEnumerator) FileSystemDriver.ResetEnumeratorError!void {
        const enumerator = getPtr(inst);

        enumerator.directory.rewind() catch |err| return switch (err) {
            error.DiskErr => return error.DiskError,
            error.IntErr => @panic("unexpected error IntErr"),
            error.InvalidObject => @panic("unexpected error InvalidObject"),
            error.OutOfMemory => @panic("unexpected error OutOfMemory"),
            error.Timeout => @panic("unexpected error Timeout"),
        };
    }

    fn next(inst: *GenericEnumerator) FileSystemDriver.EnumerateError!?ashet.abi.FileInfo {
        const enumerator = getPtr(inst);

        const next_or_null = enumerator.directory.next() catch |err| return switch (err) {
            error.DiskErr => return error.DiskError,
            error.IntErr => @panic("unexpected error IntErr"),
            error.InvalidObject => @panic("unexpected error InvalidObject"),
            error.OutOfMemory => @panic("unexpected error OutOfMemory"),
            error.Timeout => @panic("unexpected error Timeout"),
        };

        if (next_or_null) |info| {
            return .{
                .name = nameToBuf(info.name()),
                .size = info.size,
                .attributes = .{
                    .directory = (info.kind == .Directory),
                },
                .creation_date = dateTimeFromTimestamp(info.date, info.time),
                .modified_date = dateTimeFromTimestamp(info.date, info.time),
            };
        } else {
            return null;
        }
    }

    fn getPtr(p: *GenericEnumerator) *Enumerator {
        return @fieldParentPtr(Enumerator, "generic", p);
    }

    const vtable = GenericEnumerator.VTable{
        .resetFn = reset,
        .nextFn = next,
    };
};

fn nameToBuf(str: []const u8) [ashet.abi.max_file_name_len]u8 {
    var buf = std.mem.zeroes([ashet.abi.max_file_name_len]u8);
    std.mem.copyForwards(u8, &buf, str[0..@min(buf.len, str.len)]);
    return buf;
}

fn dateTimeFromTimestamp(date: fatfs.Date, time: fatfs.Time) ashet.abi.DateTime {
    // TODO: Implemen time conversion
    _ = date;
    _ = time;
    return 0;
}
