const std = @import("std");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.filesystem);
const astd = @import("ashet-std");

const storage = ashet.storage;

const fs_abi = ashet.abi.fs;

const max_file_name_len = ashet.abi.max_file_name_len;
const max_fs_name_len = ashet.abi.max_fs_name_len;
const max_fs_type_len = ashet.abi.max_fs_type_len;

const max_drives = 8;
const max_open_files = 64;

pub const File = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);

    system_resource: ashet.resources.SystemResource = .{ .type = .file },

    fs: *FileSystem,
    handle: ashet.drivers.FileSystemDriver.FileHandle,

    pub fn create(fs: *FileSystem, handle: ashet.drivers.FileSystemDriver.FileHandle) error{SystemResources}!*File {
        const dir = ashet.memory.type_pool(File).alloc() catch return error.SystemResources;
        errdefer ashet.memory.type_pool(File).free(dir);

        dir.* = .{
            .fs = fs,
            .handle = handle,
        };

        return dir;
    }

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(file: *File) void {
        file.fs.driver.closeFile(file.handle);
        ashet.memory.type_pool(File).free(file);
    }
};

pub const Directory = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);

    system_resource: ashet.resources.SystemResource = .{ .type = .directory },

    fs: *FileSystem,
    handle: ashet.drivers.FileSystemDriver.DirectoryHandle,
    iter: ?*ashet.drivers.FileSystemDriver.Enumerator = null,

    pub fn create(fs: *FileSystem, handle: ashet.drivers.FileSystemDriver.DirectoryHandle) error{SystemResources}!*Directory {
        const dir = ashet.memory.type_pool(Directory).alloc() catch return error.SystemResources;
        errdefer ashet.memory.type_pool(Directory).free(dir);

        dir.* = .{
            .fs = fs,
            .handle = handle,
        };

        return dir;
    }

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(dir: *Directory) void {
        if (dir.iter) |iter| {
            dir.fs.driver.destroyEnumerator(iter);
        }
        dir.fs.driver.closeDir(dir.handle);

        ashet.memory.type_pool(Directory).free(dir);
    }
};

fn slice_name(buf: []const u8) []const u8 {
    return buf[0 .. std.mem.indexOfScalar(u8, buf, 0) orelse buf.len];
}

var sys_disk_index: u32 = 0; // system disk index for disk named SYS:

const FileSystem = struct {
    enabled: bool,
    id: ashet.abi.FileSystemId,
    name: [ashet.abi.max_fs_name_len]u8,
    driver: *ashet.drivers.FileSystemDriver.Instance,
    block_device: *ashet.drivers.BlockDevice,
};

var filesystems: [max_drives]FileSystem = undefined;

var work_queue: ashet.overlapped.WorkQueue = undefined;

pub fn initialize() void {
    for (&filesystems) |*fs| {
        // only relevant field for init
        fs.enabled = false;
    }

    sys_disk_index = std.math.maxInt(u32);

    var first_candidate: ?u32 = null;

    var index: usize = 0;
    var devices = storage.enumerate();
    while (devices.next()) |dev| {
        if (index >= max_drives) {
            logger.err("detected more than {} potential drives!", .{max_drives});
            break;
        }

        if (dev.tags.partitioned) {
            logger.info("device {s} contains partitions, skipping", .{dev.name});
            continue;
        }

        if (!dev.isPresent()) {
            logger.info("device {s} not present, skipping", .{dev.name});
            continue;
        }

        const driver_name = ashet.drivers.getDriverName(.block, dev);

        // TODO: logger.info("device {s}: block count={}, size={}, driver={s}", .{
        //     dev.name,
        //     dev.blockCount(),
        //     std.fmt.fmtIntSizeBin(dev.byteSize()),
        //     driver_name,
        // });
        logger.info("device {s}: block count={}, size={}, driver={s}", .{
            dev.name,
            dev.blockCount(),
            dev.byteSize(),
            driver_name,
        });

        const fs = &filesystems[index];

        fs.* = FileSystem{
            .enabled = true,
            .id = @as(ashet.abi.FileSystemId, @enumFromInt(index + 1)),
            .block_device = dev,
            .name = undefined,
            .driver = undefined,
        };

        @memset(&fs.name, 0);
        std.mem.copyForwards(u8, &fs.name, dev.name);

        initFileSystem(index) catch |err| {
            logger.err("failed to initialize file system on disk {s}: {s}", .{
                dev.name,
                @errorName(err),
            });
            continue;
        };

        if (dev.tags.root_fs) {
            if (sys_disk_index != std.math.maxInt(u32)) {
                logger.warn("Multiple root file systems found. New root file system is {s}:, previous file system was {s}:", .{
                    dev.name,
                    slice_name(&filesystems[sys_disk_index].name),
                });
            }
            sys_disk_index = index;
        }
        if (first_candidate == null) {
            first_candidate = index;
        }

        index += 1;
    }

    if (sys_disk_index == std.math.maxInt(u32)) {
        sys_disk_index = first_candidate orelse @panic("No os file system found!");
        logger.warn("Could not determine explicit system fs directory, assuming file system {s}:", .{
            slice_name(&filesystems[sys_disk_index].name),
        });
    }

    logger.info("SYS: is mapped to {s}:", .{slice_name(&filesystems[sys_disk_index].name)});

    const driver_thread = ashet.scheduler.Thread.spawn(filesystemCoreLoop, null, .{
        .stack_size = 64 * 1024, // some space for copying data around
    }) catch @panic("failed to spawn filesystem thread");
    driver_thread.setName("filesystem") catch {};

    // Start the thread, we can't error (it was freshly created)
    driver_thread.start() catch unreachable;

    // and immediatly suspended the thread, so it's in a lingering state and we can wake it
    // up on demand.
    driver_thread.@"suspend"();

    work_queue = .{ .wakeup_thread = driver_thread };
}

fn resolve_dir(call: *ashet.overlapped.AsyncCall, dir: ashet.abi.Directory) error{InvalidHandle}!*Directory {
    const owner = call.resource_owner;
    return ashet.resources.resolve(Directory, owner, dir.as_resource()) catch |err| {
        logger.warn("process {} used invalid file handle {}: {s}", .{ owner, dir, @errorName(err) });
        return error.InvalidHandle;
    };
}

fn resolve_file(call: *ashet.overlapped.AsyncCall, dir: ashet.abi.File) error{InvalidHandle}!*File {
    const owner = call.resource_owner;
    return ashet.resources.resolve(File, owner, dir.as_resource()) catch |err| {
        logger.warn("process {} used invalid file handle {}: {s}", .{ owner, dir, @errorName(err) });
        return error.InvalidHandle;
    };
}

fn create_dir_handle(call: *ashet.overlapped.AsyncCall, dir: *Directory) !ashet.abi.Directory {
    const handle = try ashet.resources.add_to_process(call.resource_owner, &dir.system_resource);
    return handle.unsafe_cast(.directory);
}

fn create_file_handle(call: *ashet.overlapped.AsyncCall, file: *File) !ashet.abi.File {
    const handle = try ashet.resources.add_to_process(call.resource_owner, &file.system_resource);
    return handle.unsafe_cast(.file);
}

const iop_handlers = struct {
    fn fs_sync(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.Sync.Inputs) fs_abi.Sync.Error!fs_abi.Sync.Outputs {
        _ = call;
        _ = inputs;
        @panic("open_dir not implemented yet!");
    }

    fn fs_open_drive(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.OpenDrive.Inputs) fs_abi.OpenDrive.Error!fs_abi.OpenDrive.Outputs {
        errdefer |err| logger.warn("fs_open_drive({}) => {}", .{ inputs.fs_id, err });

        const disk_id = if (inputs.fs_id == .system)
            sys_disk_index
        else
            @intFromEnum(inputs.fs_id) - 1;

        if (!filesystems[disk_id].enabled) {
            return error.InvalidFileSystem;
        }

        const ctx = &filesystems[disk_id];

        const dri_dir = try ctx.driver.openDirFromRoot(inputs.path_ptr[0..inputs.path_len]);
        errdefer ctx.driver.closeDir(dri_dir);

        const backing = try Directory.create(ctx, dri_dir);
        errdefer backing.destroy();

        return .{ .dir = try create_dir_handle(call, backing) };
    }

    fn fs_open_dir(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.OpenDir.Inputs) fs_abi.OpenDir.Error!fs_abi.OpenDir.Outputs {
        errdefer |err| logger.warn("fs_open_dir('{s}') => {}", .{ inputs.path_ptr[0..inputs.path_len], err });

        const ctx: *Directory = try resolve_dir(call, inputs.start_dir);

        const dri_dir = try ctx.fs.driver.openDirRelative(ctx.handle, inputs.path_ptr[0..inputs.path_len]);
        errdefer ctx.fs.driver.closeDir(dri_dir);

        const backing = try Directory.create(ctx.fs, dri_dir);
        errdefer backing.destroy();

        return .{ .dir = try create_dir_handle(call, backing) };
    }

    fn fs_close_dir(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.CloseDir.Inputs) fs_abi.CloseDir.Error!fs_abi.CloseDir.Outputs {
        const ctx: *Directory = try resolve_dir(call, inputs.dir);
        ashet.resources.destroy(&ctx.system_resource);
        return .{};
    }

    fn fs_reset_dir_enumeration(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.ResetDirEnumeration.Inputs) fs_abi.ResetDirEnumeration.Error!fs_abi.ResetDirEnumeration.Outputs {
        const ctx: *Directory = try resolve_dir(call, inputs.dir);

        // Only reset an iterator if there was already one created. We don't need to reset a freshly created iterator.
        if (ctx.iter) |iter| {
            try iter.reset();
        }

        return .{};
    }

    fn fs_enumerate_dir(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.EnumerateDir.Inputs) fs_abi.EnumerateDir.Error!fs_abi.EnumerateDir.Outputs {
        const ctx: *Directory = try resolve_dir(call, inputs.dir);

        if (ctx.iter == null) {
            ctx.iter = try ctx.fs.driver.createEnumerator(ctx.handle);
        }

        const iter = ctx.iter orelse unreachable;

        if (try iter.next()) |info| {
            return .{ .eof = false, .info = info };
        } else {
            return .{ .eof = true, .info = undefined };
        }
    }

    fn fs_delete(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.Delete.Inputs) fs_abi.Delete.Error!fs_abi.Delete.Outputs {
        _ = call;
        _ = inputs;
        @panic("fs.delete not implemented yet!");
    }

    fn fs_mk_dir(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.MkDir.Inputs) fs_abi.MkDir.Error!fs_abi.MkDir.Outputs {
        _ = call;
        _ = inputs;
        @panic("fs.mkdir not implemented yet!");
    }

    fn fs_stat_entry(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.StatEntry.Inputs) fs_abi.StatEntry.Error!fs_abi.StatEntry.Outputs {
        _ = call;
        _ = inputs;
        @panic("stat_entry not implemented yet!");
    }

    fn fs_near_move(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.NearMove.Inputs) fs_abi.NearMove.Error!fs_abi.NearMove.Outputs {
        _ = call;
        _ = inputs;
        @panic("fs.nearMove not implemented yet!");
    }

    fn fs_far_move(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.FarMove.Inputs) fs_abi.FarMove.Error!fs_abi.FarMove.Outputs {
        _ = call;
        _ = inputs;
        @panic("fs.farMove not implemented yet!");
    }

    fn fs_copy(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.Copy.Inputs) fs_abi.Copy.Error!fs_abi.Copy.Outputs {
        _ = call;
        _ = inputs;
        @panic("fs.copy not implemented yet!");
    }

    fn fs_open_file(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.OpenFile.Inputs) fs_abi.OpenFile.Error!fs_abi.OpenFile.Outputs {
        errdefer |err| logger.warn("fs_open_file('{s}') => {}", .{ inputs.path_ptr[0..inputs.path_len], err });

        const ctx: *Directory = try resolve_dir(call, inputs.dir);

        const dri_file = try ctx.fs.driver.openFile(
            ctx.handle,
            inputs.path_ptr[0..inputs.path_len],
            inputs.access,
            inputs.mode,
        );
        errdefer ctx.fs.driver.closeFile(dri_file);

        const file = try File.create(
            ctx.fs,
            dri_file,
        );
        errdefer file.destroy();

        return .{ .handle = try create_file_handle(call, file) };
    }

    fn fs_close_file(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.CloseFile.Inputs) fs_abi.CloseFile.Error!fs_abi.CloseFile.Outputs {
        const ctx: *File = try resolve_file(call, inputs.file);
        ctx.destroy();
        return .{};
    }

    fn fs_flush_file(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.FlushFile.Inputs) fs_abi.FlushFile.Error!fs_abi.FlushFile.Outputs {
        const ctx: *File = try resolve_file(call, inputs.file);
        try ctx.fs.driver.flushFile(ctx.handle);
        return .{};
    }

    fn fs_read(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.Read.Inputs) fs_abi.Read.Error!fs_abi.Read.Outputs {
        const ctx: *File = try resolve_file(call, inputs.file);
        const len = try ctx.fs.driver.read(ctx.handle, inputs.offset, inputs.buffer_ptr[0..inputs.buffer_len]);
        return .{ .count = len };
    }

    fn fs_write(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.Write.Inputs) fs_abi.Write.Error!fs_abi.Write.Outputs {
        const ctx: *File = try resolve_file(call, inputs.file);
        const len = try ctx.fs.driver.write(ctx.handle, inputs.offset, inputs.buffer_ptr[0..inputs.buffer_len]);
        return .{ .count = len };
    }

    fn fs_stat_file(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.StatFile.Inputs) fs_abi.StatFile.Error!fs_abi.StatFile.Outputs {
        const ctx: *File = try resolve_file(call, inputs.file);
        const info = try ctx.fs.driver.statFile(ctx.handle);
        return .{ .info = info };
    }

    fn fs_resize(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.Resize.Inputs) fs_abi.Resize.Error!fs_abi.Resize.Outputs {
        const ctx: *File = try resolve_file(call, inputs.file);
        try ctx.fs.driver.resize(ctx.handle, inputs.length);
        return .{};
    }
};

fn filesystemCoreLoop(_: ?*anyopaque) callconv(.C) noreturn {
    const abi = ashet.abi;

    while (true) {
        while (work_queue.dequeue()) |_async_call| {
            const async_call, _ = _async_call;
            // perform the IOP here

            const type_map = .{
                .fs_sync = abi.fs.Sync,
                .fs_open_drive = abi.fs.OpenDrive,
                .fs_open_dir = abi.fs.OpenDir,
                .fs_close_dir = abi.fs.CloseDir,
                .fs_reset_dir_enumeration = abi.fs.ResetDirEnumeration,
                .fs_enumerate_dir = abi.fs.EnumerateDir,
                .fs_delete = abi.fs.Delete,
                .fs_mk_dir = abi.fs.MkDir,
                .fs_stat_entry = abi.fs.StatEntry,
                .fs_near_move = abi.fs.NearMove,
                .fs_far_move = abi.fs.FarMove,
                .fs_copy = abi.fs.Copy,
                .fs_open_file = abi.fs.OpenFile,
                .fs_close_file = abi.fs.CloseFile,
                .fs_flush_file = abi.fs.FlushFile,
                .fs_read = abi.fs.Read,
                .fs_write = abi.fs.Write,
                .fs_stat_file = abi.fs.StatFile,
                .fs_resize = abi.fs.Resize,
            };

            switch (async_call.arc.type) {
                // .fs_get_filesystem_info => iop_handlers.getFilesystemInfo(IOP.cast(abi.fs.GetFilesystemInfo, event)),

                inline .fs_sync,
                .fs_open_drive,
                .fs_open_dir,
                .fs_close_dir,
                .fs_reset_dir_enumeration,
                .fs_enumerate_dir,
                .fs_delete,
                .fs_mk_dir,
                .fs_stat_entry,
                .fs_near_move,
                .fs_far_move,
                .fs_copy,
                .fs_open_file,
                .fs_close_file,
                .fs_flush_file,
                .fs_read,
                .fs_write,
                .fs_stat_file,
                .fs_resize,
                => |tag| {
                    const T = @field(type_map, @tagName(tag));
                    const handlerFunction = @field(iop_handlers, @tagName(tag));

                    const iop = async_call.arc.cast(T);
                    async_call.finalize(T, handlerFunction(async_call, iop.inputs));
                },

                else => unreachable,
            }
        }

        ashet.scheduler.yield();
    }
}

fn initFileSystem(index: usize) !void {
    var iter = ashet.drivers.enumerate(.filesystem);
    while (iter.next()) |fs_driver| {
        filesystems[index].driver = fs_driver.createInstance(
            ashet.memory.allocator,
            filesystems[index].block_device,
        ) catch |err| {
            logger.warn("failed to initialize file system {s}: {s}, trying next one...", .{
                ashet.drivers.resolveDriver(.filesystem, fs_driver).name,
                @errorName(err),
            });
            continue;
        };
        logger.info("disk {s}: ready.", .{filesystems[index].block_device.name});
        return;
    }

    return error.UnknownOrNoFileSystem;
}

/// Checks if the path is a valid Ashet OS. path
pub fn validatePath(path: []const u8) error{InvalidPath}!void {
    if (path.len == 0)
        return error.InvalidPath;

    // path must be valid utf8
    if (!std.unicode.utf8ValidateSlice(path))
        return error.InvalidPath;

    // Paths must not start with a '/'! All paths are considered "relative" to a directory
    if (std.mem.startsWith(u8, path, "/"))
        return error.InvalidPath;

    // filter illegal characters (all ASCII control chars and '\') or if double / is present
    var prev: u8 = 0;
    for (path) |c| {
        defer prev = c;

        if (std.ascii.isControl(c))
            return error.InvalidPath;

        if (c == '/' and prev == '/')
            return error.InvalidPath;

        if (c == '\\')
            return error.InvalidPath;
    }
}

pub fn findFilesystem(name: []const u8) ?ashet.abi.FileSystemId {
    const eql = std.ascii.eqlIgnoreCase;
    if (eql(name, "SYS"))
        return .system;

    for (filesystems) |fs| {
        if (!fs.enabled)
            continue;
        if (eql(std.mem.sliceTo(&fs.name, 0), name))
            return fs.id;
    }

    return null;
}

pub fn sync(call: *ashet.overlapped.AsyncCall) void {
    work_queue.enqueue(call, null);
}

pub fn getFilesystemInfo(call: *ashet.overlapped.AsyncCall) void {
    _ = call;
    @panic("get_filesystem_info not implemented yet!");
}

pub fn openDrive(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.OpenDrive.Inputs) void {
    const disk_id = if (inputs.fs_id == .system)
        sys_disk_index
    else
        @intFromEnum(inputs.fs_id) - 1;

    if (!filesystems[disk_id].enabled) {
        return call.finalize(fs_abi.OpenDrive, error.InvalidFileSystem);
    }

    const path: []const u8 = inputs.path_ptr[0..inputs.path_len];
    validatePath(path) catch |err| {
        return call.finalize(fs_abi.OpenDrive, err);
    };

    work_queue.enqueue(call, null);
}

pub fn openDir(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.OpenDir.Inputs) void {
    _ = resolve_dir(call, inputs.start_dir) catch |err| {
        return call.finalize(fs_abi.OpenDir, err);
    };

    const path: []const u8 = inputs.path_ptr[0..inputs.path_len];
    validatePath(path) catch |err| {
        return call.finalize(fs_abi.OpenDir, err);
    };

    work_queue.enqueue(call, null);
}

pub fn closeDir(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.CloseDir.Inputs) void {
    _ = resolve_dir(call, inputs.dir) catch |err| {
        return call.finalize(fs_abi.CloseDir, err);
    };
    work_queue.enqueue(call, null);
}

pub fn resetDirEnumeration(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.ResetDirEnumeration.Inputs) void {
    _ = resolve_dir(call, inputs.dir) catch |err| {
        return call.finalize(fs_abi.ResetDirEnumeration, err);
    };
    work_queue.enqueue(call, null);
}

pub fn enumerateDir(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.EnumerateDir.Inputs) void {
    _ = resolve_dir(call, inputs.dir) catch |err| {
        return call.finalize(fs_abi.ResetDirEnumeration, err);
    };
    work_queue.enqueue(call, null);
}

pub fn delete(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.Delete.Inputs) void {
    _ = resolve_dir(call, inputs.dir) catch |err| {
        return call.finalize(fs_abi.Delete, err);
    };

    const path: []const u8 = inputs.path_ptr[0..inputs.path_len];
    validatePath(path) catch {
        return call.finalize(fs_abi.Delete, error.InvalidPath);
    };

    work_queue.enqueue(call, null);
}

pub fn mkdir(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.MkDir.Inputs) void {
    _ = resolve_dir(call, inputs.dir) catch |err| {
        return call.finalize(fs_abi.MkDir, err);
    };

    const path: []const u8 = inputs.path_ptr[0..inputs.path_len];
    validatePath(path) catch |err| {
        return call.finalize(fs_abi.MkDir, err);
    };

    work_queue.enqueue(call, null);
}

pub fn statEntry(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.StatEntry.Inputs) void {
    _ = resolve_dir(call, inputs.dir) catch |err| {
        return call.finalize(fs_abi.StatEntry, err);
    };

    const path: []const u8 = inputs.path_ptr[0..inputs.path_len];
    validatePath(path) catch |err| {
        return call.finalize(fs_abi.StatEntry, err);
    };

    work_queue.enqueue(call, null);
}

pub fn nearMove(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.NearMove.Inputs) void {
    logger.err("fs.nearMove not implemented yet!", .{});
    _ = inputs;
    call.finalize(fs_abi.NearMove, .{});
}

pub fn farMove(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.FarMove.Inputs) void {
    logger.err("fs.farMove not implemented yet!", .{});
    _ = inputs;
    call.finalize(fs_abi.FarMove, .{});
}

pub fn copy(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.Copy.Inputs) void {
    logger.err("fs.copy not implemented yet!", .{});
    _ = inputs;
    call.finalize(fs_abi.Copy, .{});
}

pub fn openFile(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.OpenFile.Inputs) void {
    _ = resolve_dir(call, inputs.dir) catch {
        return call.finalize(fs_abi.OpenFile, error.InvalidHandle);
    };

    const path: []const u8 = inputs.path_ptr[0..inputs.path_len];
    validatePath(path) catch |err| {
        return call.finalize(fs_abi.OpenFile, err);
    };

    work_queue.enqueue(call, null);
}

pub fn closeFile(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.CloseFile.Inputs) void {
    _ = resolve_file(call, inputs.file) catch |err| {
        return call.finalize(fs_abi.CloseFile, err);
    };
    work_queue.enqueue(call, null);
}

pub fn flushFile(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.FlushFile.Inputs) void {
    _ = resolve_file(call, inputs.file) catch |err| {
        return call.finalize(fs_abi.FlushFile, err);
    };
    work_queue.enqueue(call, null);
}

pub fn read(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.Read.Inputs) void {
    _ = resolve_file(call, inputs.file) catch |err| {
        return call.finalize(fs_abi.Read, err);
    };
    work_queue.enqueue(call, null);
}

pub fn write(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.Write.Inputs) void {
    _ = resolve_file(call, inputs.file) catch |err| {
        return call.finalize(fs_abi.Write, err);
    };
    work_queue.enqueue(call, null);
}

pub fn statFile(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.StatFile.Inputs) void {
    _ = resolve_file(call, inputs.file) catch |err| {
        return call.finalize(fs_abi.StatFile, err);
    };
    work_queue.enqueue(call, null);
}

pub fn resize(call: *ashet.overlapped.AsyncCall, inputs: fs_abi.Resize.Inputs) void {
    _ = resolve_file(call, inputs.file) catch |err| {
        return call.finalize(fs_abi.Resize, err);
    };
    work_queue.enqueue(call, null);
}
