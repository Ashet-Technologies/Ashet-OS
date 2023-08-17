const std = @import("std");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.filesystem);
const astd = @import("ashet-std");

const storage = ashet.storage;

const max_file_name_len = ashet.abi.max_file_name_len;
const max_fs_name_len = ashet.abi.max_fs_name_len;
const max_fs_type_len = ashet.abi.max_fs_type_len;

const max_drives = 8;
const max_open_files = 64;

const File = struct {
    fs: *FileSystem,
    handle: ashet.drivers.FileSystemDriver.FileHandle,
};

const Directory = struct {
    fs: *FileSystem,
    handle: ashet.drivers.FileSystemDriver.DirectoryHandle,
    iter: ?*ashet.drivers.FileSystemDriver.Enumerator = null,
};

var file_handles = astd.HandleAllocator(ashet.abi.FileHandle, File, max_open_files){};
var directory_handles = astd.HandleAllocator(ashet.abi.DirectoryHandle, Directory, max_open_files){};

var sys_disk_index: u32 = 0; // system disk index for disk named SYS:

const FileSystem = struct {
    enabled: bool,
    id: ashet.abi.FileSystemId,
    name: [ashet.abi.max_fs_name_len]u8,
    driver: *ashet.drivers.FileSystemDriver.Instance,
    block_device: *ashet.drivers.BlockDevice,
};

var filesystems: [max_drives]FileSystem = undefined;

var driver_thread: *ashet.scheduler.Thread = undefined;

const iop_task_queue = struct {
    var first: ?*ashet.abi.IOP = null;
    var last: ?*ashet.abi.IOP = null;

    pub fn push(task: *ashet.abi.IOP) void {
        defer std.debug.assert((first == null) == (last == null));
        if (first == null) {
            std.debug.assert(last == null);
            first = task;
            last = task;
            task.next = null;
        } else {
            std.debug.assert(last != null);
            last.?.next = task;
            task.next = null;
        }

        // Now wakeup the worker thread, there's stuff to do!
        driver_thread.@"resume"();
    }

    pub fn pop() ?*ashet.abi.IOP {
        defer std.debug.assert((first == null) == (last == null));
        if (first != null) {
            const current = first.?;

            first = current.next;
            if (first == null) {
                last = null;
            }

            current.next = null;
            return current;
        } else {
            std.debug.assert(last == null);
            return null;
        }
    }
};

pub fn initialize() void {
    for (&filesystems) |*fs| {
        // only relevant field for init
        fs.enabled = false;
    }

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
            .id = @enumFromInt(ashet.abi.FileSystemId, index + 1),
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

        if (index == 0) {
            logger.info("SYS: is mapped to {s}:", .{dev.name});
        }

        index += 1;
    }

    driver_thread = ashet.scheduler.Thread.spawn(filesystemCoreLoop, null, .{
        .stack_size = 4096, // some space for copying data around
    }) catch @panic("failed to spawn filesystem thread");
    driver_thread.setName("filesystem") catch {};

    // Start the thread, we can't error (it was freshly created)
    driver_thread.start() catch unreachable;

    // and immediatly suspended the thread, so it's in a lingering state and we can wake it
    // up on demand.
    driver_thread.@"suspend"();
}

const iop_handlers = struct {
    fn fs_sync(iop: *ashet.abi.fs.Sync) ashet.abi.fs.Sync.Error!ashet.abi.fs.Sync.Outputs {
        _ = iop;
        @panic("open_dir not implemented yet!");
    }

    fn fs_open_drive(iop: *ashet.abi.fs.OpenDrive) ashet.abi.fs.OpenDrive.Error!ashet.abi.fs.OpenDrive.Outputs {
        const disk_id = if (iop.inputs.fs == .system)
            sys_disk_index
        else
            @intFromEnum(iop.inputs.fs) - 1;

        if (!filesystems[disk_id].enabled) {
            return error.InvalidFileSystem;
        }

        const ctx = &filesystems[disk_id];

        const dri_dir = try ctx.driver.openDirFromRoot(iop.inputs.path_ptr[0..iop.inputs.path_len]);
        errdefer ctx.driver.closeDir(dri_dir);

        const handle = try directory_handles.alloc();
        errdefer directory_handles.free(handle);

        const backing = directory_handles.handleToBackingUnsafe(handle);

        backing.* = Directory{
            .fs = ctx,
            .handle = dri_dir,
            // .iter = ctx.fs.iterate(dir) catch |err| return try mapFileSystemError(err),
        };

        return .{ .dir = handle };
    }

    fn fs_open_dir(iop: *ashet.abi.fs.OpenDir) ashet.abi.fs.OpenDir.Error!ashet.abi.fs.OpenDir.Outputs {
        const ctx: *Directory = try directory_handles.resolve(iop.inputs.dir);

        const dri_dir = try ctx.fs.driver.openDirRelative(ctx.handle, iop.inputs.path_ptr[0..iop.inputs.path_len]);
        errdefer ctx.fs.driver.closeDir(dri_dir);

        const handle = try directory_handles.alloc();
        errdefer directory_handles.free(handle);

        const backing = directory_handles.handleToBackingUnsafe(handle);

        backing.* = Directory{
            .fs = ctx.fs,
            .handle = dri_dir,
        };

        return .{ .dir = handle };
    }

    fn fs_close_dir(iop: *ashet.abi.fs.CloseDir) ashet.abi.fs.CloseDir.Error!ashet.abi.fs.CloseDir.Outputs {
        const ctx: *Directory = try directory_handles.resolve(iop.inputs.dir);
        if (ctx.iter) |iter| {
            ctx.fs.driver.destroyEnumerator(iter);
        }
        ctx.fs.driver.closeDir(ctx.handle);
        directory_handles.free(iop.inputs.dir);
        return .{};
    }

    fn fs_reset_dir_enumeration(iop: *ashet.abi.fs.ResetDirEnumeration) ashet.abi.fs.ResetDirEnumeration.Error!ashet.abi.fs.ResetDirEnumeration.Outputs {
        const ctx: *Directory = try directory_handles.resolve(iop.inputs.dir);

        // Only reset an iterator if there was already one created. We don't need to reset a freshly created iterator.
        if (ctx.iter) |iter| {
            try iter.reset();
        }

        return .{};
    }

    fn fs_enumerate_dir(iop: *ashet.abi.fs.EnumerateDir) ashet.abi.fs.EnumerateDir.Error!ashet.abi.fs.EnumerateDir.Outputs {
        const ctx: *Directory = try directory_handles.resolve(iop.inputs.dir);

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

    fn fs_delete(iop: *ashet.abi.fs.Delete) ashet.abi.fs.Delete.Error!ashet.abi.fs.Delete.Outputs {
        _ = iop;
        @panic("fs.delete not implemented yet!");
    }

    fn fs_mkdir(iop: *ashet.abi.fs.MkDir) ashet.abi.fs.MkDir.Error!ashet.abi.fs.MkDir.Outputs {
        _ = iop;
        @panic("fs.mkdir not implemented yet!");
    }

    fn fs_stat_entry(iop: *ashet.abi.fs.StatEntry) ashet.abi.fs.StatEntry.Error!ashet.abi.fs.StatEntry.Outputs {
        _ = iop;
        @panic("stat_entry not implemented yet!");
    }

    fn fs_near_move(iop: *ashet.abi.fs.NearMove) ashet.abi.fs.NearMove.Error!ashet.abi.fs.NearMove.Outputs {
        _ = iop;
        @panic("fs.nearMove not implemented yet!");
    }

    fn fs_far_move(iop: *ashet.abi.fs.FarMove) ashet.abi.fs.FarMove.Error!ashet.abi.fs.FarMove.Outputs {
        _ = iop;
        @panic("fs.farMove not implemented yet!");
    }

    fn fs_copy(iop: *ashet.abi.fs.Copy) ashet.abi.fs.Copy.Error!ashet.abi.fs.Copy.Outputs {
        _ = iop;
        @panic("fs.copy not implemented yet!");
    }

    fn fs_open_file(iop: *ashet.abi.fs.OpenFile) ashet.abi.fs.OpenFile.Error!ashet.abi.fs.OpenFile.Outputs {
        const ctx: *Directory = try directory_handles.resolve(iop.inputs.dir);

        const dri_file = try ctx.fs.driver.openFile(
            ctx.handle,
            iop.inputs.path_ptr[0..iop.inputs.path_len],
            iop.inputs.access,
            iop.inputs.mode,
        );
        errdefer ctx.fs.driver.closeFile(dri_file);

        const handle = try file_handles.alloc();
        errdefer file_handles.free(handle);

        const backing = file_handles.handleToBackingUnsafe(handle);

        backing.* = File{
            .fs = ctx.fs,
            .handle = dri_file,
        };

        return .{ .handle = handle };
    }

    fn fs_close_file(iop: *ashet.abi.fs.CloseFile) ashet.abi.fs.CloseFile.Error!ashet.abi.fs.CloseFile.Outputs {
        const ctx: *File = try file_handles.resolve(iop.inputs.file);
        ctx.fs.driver.closeFile(ctx.handle);
        file_handles.free(iop.inputs.file);
        return .{};
    }

    fn fs_flush_file(iop: *ashet.abi.fs.FlushFile) ashet.abi.fs.FlushFile.Error!ashet.abi.fs.FlushFile.Outputs {
        const ctx: *File = try file_handles.resolve(iop.inputs.file);
        try ctx.fs.driver.flushFile(ctx.handle);
        return .{};
    }

    fn fs_read(iop: *ashet.abi.fs.Read) ashet.abi.fs.Read.Error!ashet.abi.fs.Read.Outputs {
        const ctx: *File = try file_handles.resolve(iop.inputs.file);
        const len = try ctx.fs.driver.read(ctx.handle, iop.inputs.offset, iop.inputs.buffer_ptr[0..iop.inputs.buffer_len]);
        return .{ .count = len };
    }

    fn fs_write(iop: *ashet.abi.fs.Write) ashet.abi.fs.Write.Error!ashet.abi.fs.Write.Outputs {
        const ctx: *File = try file_handles.resolve(iop.inputs.file);
        const len = try ctx.fs.driver.write(ctx.handle, iop.inputs.offset, iop.inputs.buffer_ptr[0..iop.inputs.buffer_len]);
        return .{ .count = len };
    }

    fn fs_stat_file(iop: *ashet.abi.fs.StatFile) ashet.abi.fs.StatFile.Error!ashet.abi.fs.StatFile.Outputs {
        const ctx: *File = try file_handles.resolve(iop.inputs.file);
        var info = try ctx.fs.driver.statFile(ctx.handle);
        return .{ .info = info };
    }

    fn fs_resize(iop: *ashet.abi.fs.Resize) ashet.abi.fs.Resize.Error!ashet.abi.fs.Resize.Outputs {
        const ctx: *File = try file_handles.resolve(iop.inputs.file);
        try ctx.fs.driver.resize(ctx.handle, iop.inputs.length);
        return .{};
    }
};

fn filesystemCoreLoop(_: ?*anyopaque) callconv(.C) noreturn {
    const IOP = ashet.abi.IOP;
    const abi = ashet.abi;

    while (true) {
        while (iop_task_queue.pop()) |event| {
            // perform the IOP here

            const type_map = .{
                .fs_sync = abi.fs.Sync,
                .fs_open_drive = abi.fs.OpenDrive,
                .fs_open_dir = abi.fs.OpenDir,
                .fs_close_dir = abi.fs.CloseDir,
                .fs_reset_dir_enumeration = abi.fs.ResetDirEnumeration,
                .fs_enumerate_dir = abi.fs.EnumerateDir,
                .fs_delete = abi.fs.Delete,
                .fs_mkdir = abi.fs.MkDir,
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

            switch (event.type) {
                // .fs_get_filesystem_info => iop_handlers.getFilesystemInfo(IOP.cast(abi.fs.GetFilesystemInfo, event)),

                inline .fs_sync,
                .fs_open_drive,
                .fs_open_dir,
                .fs_close_dir,
                .fs_reset_dir_enumeration,
                .fs_enumerate_dir,
                .fs_delete,
                .fs_mkdir,
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
                    const iop = IOP.cast(@field(type_map, @tagName(tag)), event);

                    const handlerFunction = @field(iop_handlers, @tagName(tag));
                    const err_or_result = handlerFunction(iop);
                    if (err_or_result) |result| {
                        ashet.io.finalizeWithResult(iop, result);
                    } else |err| {
                        ashet.io.finalizeWithError(iop, err);
                    }
                },

                else => unreachable,
            }
        }

        // go to sleep again until we're done.
        ashet.scheduler.Thread.current().?.@"suspend"();
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

pub fn sync(iop: *ashet.abi.fs.Sync) void {
    iop_task_queue.push(&iop.iop);
}

pub fn getFilesystemInfo(iop: *ashet.abi.fs.GetFilesystemInfo) void {
    _ = iop;
    @panic("get_filesystem_info not implemented yet!");
}

pub fn openDrive(iop: *ashet.abi.fs.OpenDrive) void {
    const disk_id = if (iop.inputs.fs == .system)
        sys_disk_index
    else
        @intFromEnum(iop.inputs.fs) - 1;

    if (!filesystems[disk_id].enabled) {
        return ashet.io.finalizeWithError(iop, error.InvalidFileSystem);
    }

    const path: []const u8 = iop.inputs.path_ptr[0..iop.inputs.path_len];
    validatePath(path) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidPath);
    };

    iop_task_queue.push(&iop.iop);
}

pub fn openDir(iop: *ashet.abi.fs.OpenDir) void {
    _ = directory_handles.resolve(iop.inputs.dir) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidHandle);
    };

    const path: []const u8 = iop.inputs.path_ptr[0..iop.inputs.path_len];
    validatePath(path) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidPath);
    };

    iop_task_queue.push(&iop.iop);
}

pub fn closeDir(iop: *ashet.abi.fs.CloseDir) void {
    _ = directory_handles.resolve(iop.inputs.dir) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidHandle);
    };
    iop_task_queue.push(&iop.iop);
}

pub fn resetDirEnumeration(iop: *ashet.abi.fs.ResetDirEnumeration) void {
    _ = directory_handles.resolve(iop.inputs.dir) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidHandle);
    };
    iop_task_queue.push(&iop.iop);
}

pub fn enumerateDir(iop: *ashet.abi.fs.EnumerateDir) void {
    _ = directory_handles.resolve(iop.inputs.dir) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidHandle);
    };
    iop_task_queue.push(&iop.iop);
}

pub fn delete(iop: *ashet.abi.fs.Delete) void {
    _ = directory_handles.resolve(iop.inputs.dir) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidHandle);
    };

    const path: []const u8 = iop.inputs.path_ptr[0..iop.inputs.path_len];
    validatePath(path) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidPath);
    };

    iop_task_queue.push(&iop.iop);
}

pub fn mkdir(iop: *ashet.abi.fs.MkDir) void {
    _ = directory_handles.resolve(iop.inputs.dir) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidHandle);
    };

    const path: []const u8 = iop.inputs.path_ptr[0..iop.inputs.path_len];
    validatePath(path) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidPath);
    };

    iop_task_queue.push(&iop.iop);
}

pub fn statEntry(iop: *ashet.abi.fs.StatEntry) void {
    _ = directory_handles.resolve(iop.inputs.dir) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidHandle);
    };

    const path: []const u8 = iop.inputs.path_ptr[0..iop.inputs.path_len];
    validatePath(path) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidPath);
    };

    iop_task_queue.push(&iop.iop);
}

pub fn nearMove(iop: *ashet.abi.fs.NearMove) void {
    std.log.err("fs.nearMove not implemented yet!", .{});
    ashet.io.finalizeWithResult(iop, .{});
}

pub fn farMove(iop: *ashet.abi.fs.FarMove) void {
    std.log.err("fs.farMove not implemented yet!", .{});
    ashet.io.finalizeWithResult(iop, .{});
}

pub fn copy(iop: *ashet.abi.fs.Copy) void {
    std.log.err("fs.copy not implemented yet!", .{});
    ashet.io.finalizeWithResult(iop, .{});
}

pub fn openFile(iop: *ashet.abi.fs.OpenFile) void {
    _ = directory_handles.resolve(iop.inputs.dir) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidHandle);
    };

    const path: []const u8 = iop.inputs.path_ptr[0..iop.inputs.path_len];
    validatePath(path) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidPath);
    };

    iop_task_queue.push(&iop.iop);
}

pub fn closeFile(iop: *ashet.abi.fs.CloseFile) void {
    _ = file_handles.resolve(iop.inputs.file) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidHandle);
    };

    iop_task_queue.push(&iop.iop);
}

pub fn flushFile(iop: *ashet.abi.fs.FlushFile) void {
    _ = file_handles.resolve(iop.inputs.file) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidHandle);
    };

    iop_task_queue.push(&iop.iop);
}

pub fn read(iop: *ashet.abi.fs.Read) void {
    _ = file_handles.resolve(iop.inputs.file) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidHandle);
    };

    iop_task_queue.push(&iop.iop);
}

pub fn write(iop: *ashet.abi.fs.Write) void {
    _ = file_handles.resolve(iop.inputs.file) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidHandle);
    };

    iop_task_queue.push(&iop.iop);
}

pub fn statFile(iop: *ashet.abi.fs.StatFile) void {
    _ = file_handles.resolve(iop.inputs.file) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidHandle);
    };

    iop_task_queue.push(&iop.iop);
}

pub fn resize(iop: *ashet.abi.fs.Resize) void {
    _ = file_handles.resolve(iop.inputs.file) catch {
        return ashet.io.finalizeWithError(iop, error.InvalidHandle);
    };

    iop_task_queue.push(&iop.iop);
}
