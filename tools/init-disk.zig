const std = @import("std");
const fatfs = @import("fatfs");

// requires pointer stability
var global_fs: fatfs.FileSystem = undefined;

// requires pointer stability
var image_disk: Disk = .{};

pub const log_level = .info;

pub const std_options = struct {
    pub const log_scope_levels = &.{
        std.log.ScopeLevel{ .scope = .fatfs, .level = .warn },
        std.log.ScopeLevel{ .scope = .disk, .level = .warn },
    };
};

pub fn main() !u8 {
    const args = try std.process.argsAlloc(std.heap.c_allocator);
    defer std.process.argsFree(std.heap.c_allocator, args);

    if (args.len != 2) {
        std.log.err("init-disk <image>!", .{});
        return 1;
    }

    image_disk.create(args[1], 32 * 1024 * 1024) catch |e| {
        std.log.err("failed to open disk {s}: {s}", .{ args[1], @errorName(e) });
        return 1;
    };
    defer image_disk.close();

    fatfs.disks[0] = &image_disk.interface;

    // Format the disk
    {
        var workspace: [8192]u8 = undefined;
        try fatfs.mkfs("0", .{
            .filesystem = .any,
            .sector_align = 512,
        }, &workspace);
    }

    try global_fs.mount("0:", true);
    defer fatfs.FileSystem.unmount("0:") catch |e| std.log.err("failed to unmount filesystem: {s}", .{@errorName(e)});

    // Root structure
    try makeDir("apps");
    try makeDir("etc");
    try makeDir("docs");

    // populate root
    {
        var rootfs = try std.fs.cwd().openIterableDir("rootfs", .{});
        defer rootfs.close();

        var walker = try rootfs.walk(std.heap.c_allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind == .Directory) {
                try makeDir(entry.path);
            } else if (entry.kind == .File) {
                try copyDirFileTo(
                    entry.dir,
                    entry.basename,
                    entry.path,
                    std.mem.eql(u8, std.fs.path.extension(entry.basename), ".txt"),
                );
            } else {
                std.log.err("{s} has unsupported kind {}", .{ entry.path, entry.kind });
            }
        }
    }

    // install apps
    {
        var walker = try std.fs.cwd().openIterableDir("zig-out/apps", .{});
        defer walker.close();

        var iter = walker.iterate();

        while (try iter.next()) |entry| {
            if (entry.kind != .File)
                continue;
            const ext = std.fs.path.extension(entry.name);
            if (!std.mem.eql(u8, ext, ".app"))
                continue;

            const basename = entry.name[0 .. entry.name.len - ext.len];

            var app_root_buf: [1024]u8 = undefined;
            const app_root = try std.fmt.bufPrint(&app_root_buf, "apps/{s}", .{basename});
            try makeDir(app_root);

            const app_code = try std.fmt.bufPrint(&app_root_buf, "apps/{s}/code", .{basename});
            try copyDirFileTo(walker.dir, entry.name, app_code, false);

            var icon_buf: [1024]u8 = undefined;
            const icon = try std.fmt.bufPrint(&icon_buf, "{s}.icon", .{basename});

            const app_icon = try std.fmt.bufPrint(&app_root_buf, "apps/{s}/icon", .{basename});
            copyDirFileTo(walker.dir, icon, app_icon, false) catch |err| switch (err) {
                error.FileNotFound => {}, // that's okay
                else => |e| return e,
            };
        }
    }

    var items: [max_walk_depth]bool = undefined;
    try std.io.getStdOut().writeAll("DISK:\n");
    try walkDir("/", items[0..0]);

    return 0;
}

const max_walk_depth = 32;

fn walkDir(path: fatfs.Path, levels: []bool) !void {
    if (levels.len == max_walk_depth)
        return;
    var dir = try fatfs.Dir.open(path);
    defer dir.close();

    var stdout = std.io.getStdOut();
    var writer = stdout.writer();

    var it = try dir.next();

    var superslice = levels;
    const d = superslice.len;
    superslice.len += 1;

    while (it) |fi| {
        it = try dir.next();
        const has_next = (it != null);
        superslice[d] = has_next;

        for (levels) |lvl| {
            try writer.writeAll(if (lvl) "|   " else "    ");
        }

        try writer.writeAll(if (has_next) "|" else "'");
        try writer.print("-- {s}\n", .{fi.name()});
        switch (fi.kind) {
            .Directory => {
                var subdir_buf: [4096]u8 = undefined;
                const subdir = try std.fmt.bufPrintZ(&subdir_buf, "{s}/{s}", .{ path, fi.name() });
                try walkDir(subdir, superslice);
            },
            else => {},
        }
    }
}

fn makeDir(path: []const u8) !void {
    std.debug.assert(!std.fs.path.isAbsolutePosix(path));
    var dest_path_buffer: [1024]u8 = undefined;
    const dest_path = try std.fmt.bufPrintZ(&dest_path_buffer, "0:/{s}", .{path});
    fatfs.mkdir(dest_path) catch |err| switch (err) {
        error.Exist => {},
        else => |e| return e,
    };
}

fn copyFileTo(source: []const u8, dest: []const u8, unix2dos: bool) !void {
    return copyDirFileTo(std.fs.cwd(), source, dest, unix2dos);
}

fn copyDirFileTo(src_dir: std.fs.Dir, source: []const u8, dest: []const u8, unix2dos: bool) !void {
    std.debug.assert(!std.fs.path.isAbsolutePosix(dest));

    if (std.fs.path.dirname(dest)) |dir| {
        try makeDir(dir);
    }

    var source_file = try src_dir.openFile(source, .{});
    defer source_file.close();

    var dest_path_buffer: [1024]u8 = undefined;
    const dest_path = try std.fmt.bufPrintZ(&dest_path_buffer, "0:/{s}", .{dest});

    var file = try fatfs.File.create(dest_path);
    defer file.close();

    if (unix2dos) {
        var buffered_in = std.io.bufferedReader(source_file.reader());
        var buffered_out = std.io.bufferedWriter(file.writer());

        var reader = buffered_in.reader();
        var writer = buffered_out.writer();

        var line_buffer: [4096]u8 = undefined;

        while (true) {
            const line_or_null = try reader.readUntilDelimiterOrEof(&line_buffer, '\n');
            const line = line_or_null orelse break;
            try writer.writeAll(line);
            try writer.writeAll("\r\n");
        }

        try buffered_out.flush();
    } else {
        var fifo = std.fifo.LinearFifo(u8, .{ .Static = 8192 }).init();
        try fifo.pump(source_file.reader(), file.writer());
    }
}

pub const Disk = struct {
    const sector_size = 512;
    const logger = std.log.scoped(.disk);

    interface: fatfs.Disk = fatfs.Disk{
        .getStatusFn = getStatus,
        .initializeFn = initialize,
        .readFn = read,
        .writeFn = write,
        .ioctlFn = ioctl,
    },
    backing_file: ?std.fs.File = null,

    fn open(self: *Disk, path: []const u8) !void {
        self.close();
        self.backing_file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
    }

    fn create(self: *Disk, path: []const u8, size: u64) !void {
        self.close();
        var file = try std.fs.cwd().createFile(path, .{ .read = true });
        try file.seekTo(size - 1);
        try file.writeAll(".");
        self.backing_file = file;
    }

    fn close(self: *Disk) void {
        if (self.backing_file) |*file| {
            file.close();
            self.backing_file = null;
        }
    }

    pub fn getStatus(interface: *fatfs.Disk) fatfs.Disk.Status {
        const self = @fieldParentPtr(Disk, "interface", interface);
        return fatfs.Disk.Status{
            .initialized = (self.backing_file != null),
            .disk_present = (self.backing_file != null),
            .write_protected = false,
        };
    }

    pub fn initialize(interface: *fatfs.Disk) fatfs.Disk.Error!fatfs.Disk.Status {
        const self = @fieldParentPtr(Disk, "interface", interface);
        if (self.backing_file != null) {
            return fatfs.Disk.Status{
                .initialized = true,
                .disk_present = true,
                .write_protected = false,
            };
        }
        return fatfs.Disk.Status{
            .initialized = false,
            .disk_present = false,
            .write_protected = false,
        };
    }

    pub fn read(interface: *fatfs.Disk, buff: [*]u8, sector: fatfs.LBA, count: c_uint) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(Disk, "interface", interface);

        logger.debug("read({*}, {}, {})", .{ buff, sector, count });

        var file = self.backing_file orelse return error.DiskNotReady;
        file.seekTo(sector * sector_size) catch return error.IoError;
        file.reader().readNoEof(buff[0 .. sector_size * count]) catch return error.IoError;
    }

    pub fn write(interface: *fatfs.Disk, buff: [*]const u8, sector: fatfs.LBA, count: c_uint) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(Disk, "interface", interface);

        logger.debug("write({*}, {}, {})", .{ buff, sector, count });

        var file = self.backing_file orelse return error.DiskNotReady;
        file.seekTo(sector * sector_size) catch return error.IoError;
        file.writer().writeAll(buff[0 .. sector_size * count]) catch return error.IoError;
    }

    pub fn ioctl(interface: *fatfs.Disk, cmd: fatfs.IoCtl, buff: [*]u8) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(Disk, "interface", interface);
        if (self.backing_file) |file| {
            switch (cmd) {
                .sync => {
                    file.sync() catch return error.IoError;
                },

                .get_sector_count => {
                    const size = @ptrCast(*fatfs.LBA, @alignCast(@alignOf(fatfs.LBA), buff));
                    const len = file.getEndPos() catch return error.IoError;
                    size.* = @intCast(fatfs.LBA, len / 512);
                },
                .get_sector_size => {
                    const size = @ptrCast(*fatfs.WORD, @alignCast(@alignOf(fatfs.WORD), buff));
                    size.* = 512;
                },
                .get_block_size => {
                    const size = @ptrCast(*fatfs.DWORD, @alignCast(@alignOf(fatfs.DWORD), buff));
                    size.* = 1;
                },

                else => return error.InvalidParameter,
            }
        } else {
            return error.DiskNotReady;
        }
    }
};
