const std = @import("std");
const fatfs = @import("zfat");

// const hdr = @cImport({
//     @cInclude("syslinux-mtools.h");
// });

pub extern fn main() c_int;

var fat_disk: fatfs.Disk = .{
    .getStatusFn = disk_getStatus,
    .initializeFn = disk_initialize,
    .readFn = disk_read,
    .writeFn = disk_write,
    .ioctlFn = disk_ioctl,
};

fn get_string(maybe: ?[*:0]const u8) [:0]const u8 {
    return std.mem.sliceTo(
        maybe orelse @panic("invalid argument"),
        0,
    );
}

fn get_slice(maybe: ?[*]const u8, len: usize) []const u8 {
    if (len == 0)
        return &.{};
    const ptr = maybe orelse @panic("invalid arg");
    return ptr[0..len];
}

var global_disk_fd: std.posix.fd_t = -1;
var global_disk_offset: u64 = 0;

var global_fs: fatfs.FileSystem = undefined;

pub export fn mtools_configure(fd: std.posix.fd_t, offset: u64) bool {
    std.log.info("mtools_configure({}, {})", .{ fd, offset });
    global_disk_fd = fd;
    global_disk_offset = offset;

    fatfs.disks[0] = &fat_disk;

    return true;
}

fn setup() bool {
    if (global_disk_fd == -1) {
        std.log.err("system not set up", .{});
        return false;
    }
    global_fs.mount("0:", true) catch |err| {
        std.log.err("failed to mount disk 0: {s}", .{@errorName(err)});
        return false;
    };
    return true;
}

fn teardown() void {
    fatfs.FileSystem.unmount("0:") catch |err| {
        std.log.err("failed to unmount disk 0: {s}", .{@errorName(err)});
        @panic("nonrecoverable!");
    };
}

fn assert_path(disk_path: []const u8) void {
    if (std.mem.startsWith(u8, disk_path, "s:/"))
        return;
    std.debug.panic("Path '{}' does not start with expected 's:/'!", .{
        std.zig.fmtEscapes(disk_path),
    });
}

pub export fn mtools_flags_clear(maybe_disk_path: ?[*:0]const u8) bool {
    const disk_path = get_string(maybe_disk_path);

    if (!setup())
        return false;
    defer teardown();

    std.log.debug("mtools_flags_clear('{}')", .{std.zig.fmtEscapes(disk_path)});

    assert_path(disk_path);

    fatfs.chmod(disk_path[3..], .{ .read_only = false, .hidden = false, .system = false }) catch |err| {
        std.log.err("failed to clear flags for '{s}': {s}", .{ disk_path, @errorName(err) });
        return false;
    };

    return true;
}

pub export fn mtools_flags_set(maybe_disk_path: ?[*:0]const u8) bool {
    const disk_path = get_string(maybe_disk_path);

    if (!setup())
        return false;
    defer teardown();

    std.log.debug("mtools_flags_set('{}')", .{std.zig.fmtEscapes(disk_path)});

    assert_path(disk_path);

    fatfs.chmod(disk_path[3..], .{ .read_only = true, .hidden = true, .system = true }) catch |err| {
        std.log.err("failed to set flags for '{s}': {s}", .{ disk_path, @errorName(err) });
        return false;
    };

    return true;
}

pub export fn mtools_create_file(
    maybe_disk_path: ?[*:0]const u8,
    disk_data1_ptr: ?[*]const u8,
    disk_data1_len: usize,
    disk_data2_ptr: ?[*]const u8,
    disk_data2_len: usize,
) bool {
    const disk_path = get_string(maybe_disk_path);
    const data1 = get_slice(disk_data1_ptr, disk_data1_len);
    const data2 = get_slice(disk_data2_ptr, disk_data2_len);

    if (!setup())
        return false;
    defer teardown();

    std.log.debug("mtools_copy_file('{}', '{}', '{}')", .{
        std.zig.fmtEscapes(disk_path),
        std.fmt.fmtSliceHexLower(data1),
        std.fmt.fmtSliceHexLower(data2),
    });

    assert_path(disk_path);

    var file = fatfs.File.create(disk_path[3..]) catch |err| {
        std.log.err("failed to create file '{s}': {s}", .{ disk_path, @errorName(err) });
        return false;
    };
    defer file.close();

    file.writer().writeAll(data1) catch |err| {
        std.log.err("failed to write data1 to file '{s}': {s}", .{ disk_path, @errorName(err) });
        return false;
    };
    file.writer().writeAll(data2) catch |err| {
        std.log.err("failed to write data1 to file '{s}': {s}", .{ disk_path, @errorName(err) });
        return false;
    };

    return true;
}

pub export fn mtools_move_file(maybe_disk_path_old: ?[*:0]const u8, maybe_disk_path_new: ?[*:0]const u8) bool {
    const disk_path_old = get_string(maybe_disk_path_old);
    const disk_path_new = get_string(maybe_disk_path_new);

    if (!setup())
        return false;
    defer teardown();


    std.log.debug("mtools_move_file('{}', '{}')", .{
        std.zig.fmtEscapes(disk_path_old),
        std.zig.fmtEscapes(disk_path_new),
    });

    assert_path(disk_path_old);
    assert_path(disk_path_new);

    fatfs.rename(disk_path_old, disk_path_new) catch |err| {
        std.log.err("failed to move file from '{s}' to '{s}': {s}", .{ disk_path_old, disk_path_new, @errorName(err) });
        return false;
    };

    return true ;
}

fn disk_getStatus(intf: *fatfs.Disk) fatfs.Disk.Status {
    _ = intf;
    return .{
        .initialized = true,
        .disk_present = true,
        .write_protected = false,
    };
}

fn disk_initialize(intf: *fatfs.Disk) fatfs.Disk.Error!fatfs.Disk.Status {
    return disk_getStatus(intf);
}

fn disk_read(intf: *fatfs.Disk, buff: [*]u8, sector: fatfs.LBA, count: c_uint) fatfs.Disk.Error!void {
    _ = intf;

    const chunk = buff[0 .. 512 * count];

    const offset = global_disk_offset + 512 * sector;

    std.posix.lseek_SET(global_disk_fd, offset) catch return error.IoError;

    const len = std.posix.read(global_disk_fd, chunk) catch return error.IoError;
    if (len != chunk.len)
        @panic("missed read");
}

fn disk_write(intf: *fatfs.Disk, buff: [*]const u8, sector: fatfs.LBA, count: c_uint) fatfs.Disk.Error!void {
    _ = intf;

    const chunk = buff[0 .. 512 * count];

    const offset = global_disk_offset + 512 * sector;

    std.posix.lseek_SET(global_disk_fd, offset) catch return error.IoError;

    const len = std.posix.write(global_disk_fd, chunk) catch return error.IoError;
    if (len != chunk.len)
        @panic("missed write");
}

fn disk_ioctl(intf: *fatfs.Disk, cmd: fatfs.IoCtl, buff: [*]u8) fatfs.Disk.Error!void {
    _ = intf;

    switch (cmd) {
        .sync => std.posix.syncfs(global_disk_fd) catch return error.IoError,

        .get_sector_count => {
            const stat = std.posix.fstat(global_disk_fd) catch return error.IoError;

            const size: *fatfs.LBA = @ptrCast(@alignCast(buff));
            size.* = @intCast(@divTrunc(stat.size, 512));
        },
        .get_sector_size => {
            const size: *fatfs.WORD = @ptrCast(@alignCast(buff));
            size.* = 512;
        },
        .get_block_size => {
            const size: *fatfs.DWORD = @ptrCast(@alignCast(buff));
            size.* = 1;
        },

        else => return error.InvalidParameter,
    }
}
