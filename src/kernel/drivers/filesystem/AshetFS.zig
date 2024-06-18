const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.@"ashet fs");
const afs = @import("ashet-fs");

const FileSystemDriver = ashet.drivers.FileSystemDriver;
const GenericInstance = ashet.drivers.FileSystemDriver.Instance;
const GenericEnumerator = ashet.drivers.FileSystemDriver.Enumerator;

pub var driver = ashet.drivers.Driver{
    .name = "Ashet FS",
    .class = .{
        .filesystem = .{
            .createInstanceFn = createInstance,
            .destroyInstanceFn = destroyInstance,
        },
    },
};

const FileHandle = ashet.drivers.FileSystemDriver.FileHandle;
const DirectoryHandle = ashet.drivers.FileSystemDriver.DirectoryHandle;
const Block = afs.Block;

/// AshetFS driver block device wrapper
const BlockDevice = struct {
    const BD = @This();

    backing: *ashet.storage.BlockDevice,

    pub fn interface(bd: *BD) afs.BlockDevice {
        return afs.BlockDevice{
            .object = bd,
            .vtable = &vtable,
        };
    }

    fn fromCtx(ctx: *anyopaque) *BD {
        return @ptrCast(@alignCast(ctx));
    }

    fn getBlockCount(ctx: *anyopaque) u32 {
        // We can "safely" truncate here to 2TB storage for now.
        return std.math.cast(u32, fromCtx(ctx).backing.blockCount()) orelse std.math.maxInt(u32);
    }

    fn writeBlock(ctx: *anyopaque, offset: u32, block: *const Block) afs.BlockDevice.IoError!void {
        fromCtx(ctx).backing.writeBlock(offset, block) catch |err| switch (err) {
            error.Fault, error.DeviceNotPresent => return error.DeviceError,
            error.Timeout => return error.OperationTimeout,
            error.NotSupported => return error.WriteProtected,
            error.InvalidBlock => @panic("bug in filesystem driver!"),
        };
    }

    fn readBlock(ctx: *anyopaque, offset: u32, block: *Block) afs.BlockDevice.IoError!void {
        fromCtx(ctx).backing.readBlock(offset, block) catch |err| switch (err) {
            error.Fault, error.DeviceNotPresent => return error.DeviceError,
            error.Timeout => return error.OperationTimeout,
            error.InvalidBlock => @panic("bug in filesystem driver!"),
        };
    }

    const vtable = afs.BlockDevice.VTable{
        .getBlockCountFn = getBlockCount,
        .writeBlockFn = writeBlock,
        .readBlockFn = readBlock,
    };
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
        .fs = undefined,
    };
    errdefer instance.enumerator_pool.deinit();

    instance.init() catch |err| switch (err) {
        error.OperationTimeout => return error.DeviceError,
        error.WriteProtected => return error.DeviceError,
        error.UnsupportedVersion => return error.NoFilesystem,
        else => |e| return e,
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

const Instance = struct {
    generic: GenericInstance,
    block_device: BlockDevice,
    fs: afs.FileSystem,
    enumerator_pool: std.heap.MemoryPool(Enumerator),
    cache: afs.FileDataCache = .{},

    fn init(instance: *Instance) !void {
        instance.fs = try afs.FileSystem.init(instance.block_device.interface());
    }

    fn deinit(instance: *Instance) void {
        instance.enumerator_pool.deinit();
        instance.* = undefined;
    }

    fn openDirFromRoot(generic: *GenericInstance, path: []const u8) FileSystemDriver.OpenDirAbsError!DirectoryHandle {
        const instance = getPtr(generic);

        const dir = resolvePath(&instance.fs, instance.fs.root_directory, path, .directory) catch |err| return try mapFileSystemError(err);

        return enumCast(DirectoryHandle, dir);
    }

    fn openDirRelative(generic: *GenericInstance, base_dir: DirectoryHandle, path: []const u8) FileSystemDriver.OpenDirRelError!DirectoryHandle {
        const instance = getPtr(generic);

        const dir = resolvePath(&instance.fs, enumCast(afs.DirectoryHandle, base_dir), path, .directory) catch |err| return try mapFileSystemError(err);

        return enumCast(DirectoryHandle, dir);
    }

    fn closeDir(generic: *GenericInstance, dir: DirectoryHandle) void {
        const instance = getPtr(generic);

        _ = instance;
        _ = dir;
    }

    fn openFile(generic: *GenericInstance, base_dir: DirectoryHandle, path: []const u8, access: ashet.abi.FileAccess, mode: ashet.abi.FileMode) FileSystemDriver.OpenFileError!FileHandle {
        const instance = getPtr(generic);

        _ = access;
        _ = mode;

        const fs_file = resolvePath(&instance.fs, enumCast(afs.DirectoryHandle, base_dir), path, .file) catch |err| return try mapFileSystemError(err);

        return enumCast(FileHandle, fs_file);
    }

    fn closeFile(generic: *GenericInstance, dir: FileHandle) void {
        const instance = getPtr(generic);

        _ = instance;
        _ = dir;
    }

    fn read(generic: *GenericInstance, file_handle: FileHandle, offset: u64, buffer: []u8) FileSystemDriver.ReadError!usize {
        const instance = getPtr(generic);

        return instance.fs.readData(enumCast(afs.FileHandle, file_handle), offset, buffer, &instance.cache) catch |err| return try mapFileSystemError(err);
    }

    fn write(generic: *GenericInstance, file_handle: FileHandle, offset: u64, buffer: []const u8) FileSystemDriver.WriteError!usize {
        const instance = getPtr(generic);

        return instance.fs.writeData(enumCast(afs.FileHandle, file_handle), offset, buffer, &instance.cache) catch |err| return try mapFileSystemError(err);
    }

    fn statFile(generic: *GenericInstance, file_handle: FileHandle) FileSystemDriver.StatFileError!ashet.abi.FileInfo {
        const instance = getPtr(generic);

        const meta = instance.fs.readMetaData(enumCast(afs.ObjectHandle, file_handle)) catch |err| return try mapFileSystemError(err);

        return ashet.abi.FileInfo{
            .name = std.mem.zeroes([120]u8),
            .size = meta.size,
            .attributes = .{ .directory = false },
            .creation_date = dateTimeFromTimestamp(meta.create_time),
            .modified_date = dateTimeFromTimestamp(meta.modify_time),
        };
    }

    fn createEnumerator(generic_instance: *GenericInstance, directory_handle: DirectoryHandle) FileSystemDriver.CreateEnumeratorError!*GenericEnumerator {
        const instance = getPtr(generic_instance);

        const enumerator = instance.enumerator_pool.create() catch return error.SystemResources;
        errdefer instance.enumerator_pool.destroy(enumerator);

        enumerator.* = Enumerator{
            .generic = .{
                .instance = generic_instance,
                .vtable = &Enumerator.vtable,
            },
            .directory = enumCast(afs.DirectoryHandle, directory_handle),
            .iterator = undefined,
        };

        // will initialize the enumerator properly
        try enumerator.generic.reset();

        return &enumerator.generic;
    }

    fn destroyEnumerator(generic_instance: *GenericInstance, generic_enumerator: *GenericEnumerator) void {
        const instance = getPtr(generic_instance);
        const enumerator = Enumerator.getPtr(generic_enumerator);

        instance.enumerator_pool.destroy(enumerator);
    }

    fn getPtr(p: *GenericInstance) *Instance {
        return @fieldParentPtr("generic", p);
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
    directory: afs.DirectoryHandle,
    iterator: afs.FileSystem.Iterator,

    fn reset(inst: *GenericEnumerator) FileSystemDriver.ResetEnumeratorError!void {
        const enumerator = getPtr(inst);
        const parent = Instance.getPtr(inst.instance);

        // work around RLS
        const iter = parent.fs.iterate(enumerator.directory) catch |err| return try mapFileSystemError(err);
        enumerator.iterator = iter;
    }

    fn next(inst: *GenericEnumerator) FileSystemDriver.EnumerateError!?ashet.abi.FileInfo {
        const enumerator = getPtr(inst);
        const parent = Instance.getPtr(inst.instance);

        const next_or_null = enumerator.iterator.next() catch |err| return try mapFileSystemError(err);

        if (next_or_null) |info| {
            const stat = parent.fs.readMetaData(info.handle.object()) catch |err| return try mapFileSystemError(err);

            return .{
                .name = info.name_buffer,
                .size = stat.size,
                .attributes = .{
                    .directory = (info.handle == .directory),
                },
                .creation_date = dateTimeFromTimestamp(stat.create_time),
                .modified_date = dateTimeFromTimestamp(stat.modify_time),
            };
        } else {
            return null;
        }
    }

    fn getPtr(p: *GenericEnumerator) *Enumerator {
        return @fieldParentPtr("generic", p);
    }

    const vtable = GenericEnumerator.VTable{
        .resetFn = reset,
        .nextFn = next,
    };
};

const EntryType = enum {
    object,
    directory,
    file,

    pub fn ResultType(comptime et: EntryType) type {
        return switch (et) {
            .object => afs.Entry.Handle,
            .directory => afs.DirectoryHandle,
            .file => afs.FileHandle,
        };
    }

    pub fn map(comptime et: EntryType, value: afs.Entry.Handle) error{InvalidObject}!et.ResultType() {
        return switch (et) {
            .object => value,
            .directory => switch (value) {
                .directory => |d| d,
                else => return error.InvalidObject,
            },
            .file => switch (value) {
                .file => |f| f,
                else => return error.InvalidObject,
            },
        };
    }
};

fn resolvePath(fs: *afs.FileSystem, root_dir: afs.DirectoryHandle, path: []const u8, comptime expected: EntryType) !expected.ResultType() {
    try ashet.filesystem.validatePath(path);

    var current_dir = root_dir;

    var splitter = std.mem.tokenize(u8, path, "/");

    if (splitter.next()) |first_element| {
        var next_element: ?[]const u8 = first_element;
        while (next_element) |current_element| {
            next_element = splitter.next();

            const entry = try fs.getEntry(current_dir, current_element);

            if (next_element != null) {
                // subdir
                if (entry.handle != .directory)
                    return error.FileNotFound; // maybe a better error here?

                current_dir = entry.handle.directory;
            } else {
                // terminal element
                return try expected.map(entry.handle);
            }
        }
        unreachable;
    } else {
        return expected.map(.{ .directory = current_dir });
    }
}

fn mapFileSystemError(err: anytype) !noreturn {
    const E = @TypeOf(err) || error{
        InvalidObject,
        DeviceError,
        OperationTimeout,
        WriteProtected,
        CorruptFilesystem,
    };

    return switch (@as(E, err)) {
        error.InvalidObject => return error.DiskError,
        error.DeviceError => return error.DiskError,
        error.OperationTimeout => return error.DiskError,
        error.WriteProtected => return error.DiskError,
        error.CorruptFilesystem => return error.DiskError,
        else => |e| return e,
    };
}

fn dateTimeFromTimestamp(ts: i128) ashet.abi.DateTime {
    return @as(i64, @intCast(@divTrunc(ts, std.time.ns_per_ms)));
}
