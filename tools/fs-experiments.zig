const std = @import("std");

const fatfs = @import("fatfs");

// requires pointer stability
var global_fs: fatfs.FileSystem = undefined;

// requires pointer stability
var image_disk: Disk = .{};

pub fn main() !u8 {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len != 2) {
        std.log.err("requires source file!", .{});
        return 1;
    }

    var source_file = std.fs.cwd().openFile(args[1], .{}) catch |e| {
        std.log.err("failed to open firmware {s}: {s}", .{ args[1], @errorName(e) });
        return 1;
    };
    defer source_file.close();

    image_disk.open(args[1]) catch |e| {
        std.log.err("failed to open disk /dev/sdb1: {s}", .{@errorName(e)});
        return 1;
    };
    defer image_disk.close();

    fatfs.disks[0] = &image_disk.interface;

    try global_fs.mount("0:", true);
    defer fatfs.FileSystem.unmount("0:") catch |e| std.log.err("failed to unmount filesystem: {s}", .{@errorName(e)});

    {
        var dir = try fatfs.Dir.open("/");
        defer dir.close();

        while (try dir.next()) |ent| {
            std.log.info("entry: {{ fsize={}, fdate={}, ftime={}, fattrib={}, altname='{}', fname='{}' }}", .{
                ent.fsize,
                ent.fdate,
                ent.ftime,
                ent.fattrib,
                std.fmt.fmtSliceEscapeUpper(std.mem.sliceTo(&ent.altname, 0)),
                std.fmt.fmtSliceEscapeUpper(std.mem.sliceTo(&ent.fname, 0)),
            });
        }
    }

    return 0;
}

pub const Disk = struct {
    const sector_size = 512;

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
        self.backing_file = std.fs.cwd().openFile("disk.img", .{ .mode = .read_write }) catch return error.DiskNotReady;
        return fatfs.Disk.Status{
            .initialized = (self.backing_file != null),
            .disk_present = (self.backing_file != null),
            .write_protected = false,
        };
    }

    pub fn read(interface: *fatfs.Disk, buff: [*]u8, sector: fatfs.LBA, count: c_uint) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(Disk, "interface", interface);

        std.log.info("read({*}, {}, {})", .{ buff, sector, count });

        var file = self.backing_file orelse return error.IoError;
        file.seekTo(sector * sector_size) catch return error.IoError;
        file.reader().readNoEof(buff[0 .. sector_size * count]) catch return error.IoError;

        std.log.info("{} => {}", .{sector,std.fmt.fmtSliceHexLower(buff[0 .. sector_size * count])});
    }

    pub fn write(interface: *fatfs.Disk, buff: [*]const u8, sector: fatfs.LBA, count: c_uint) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(Disk, "interface", interface);

        std.log.info("write({*}, {}, {})", .{ buff, sector, count });

        var file = self.backing_file orelse return error.IoError;
        file.seekTo(sector * sector_size) catch return error.IoError;
        file.writer().writeAll(buff[0 .. sector_size * count]) catch return error.IoError;
    }

    pub fn ioctl(interface: *fatfs.Disk, cmd: fatfs.IoCtl, buff: [*]u8) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(Disk, "interface", interface);
        if (self.backing_file) |file| {
            _ = buff;
            switch (cmd) {
                .sync => {
                    file.sync() catch return error.IoError;
                },

                else => return error.InvalidParameter,
            }
        } else {
            return error.DiskNotReady;
        }
    }
};
