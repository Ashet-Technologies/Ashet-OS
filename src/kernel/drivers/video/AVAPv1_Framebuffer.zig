const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.ashet_fb);
const machine = ashet.machine.peripherals;

const AVAPv1_Framebuffer = @This();
const Driver = ashet.drivers.Driver;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

pub const width = 640;
pub const height = 400;

driver: Driver = .{
    .name = "AVAPv1 Framebuffer",
    .class = .{
        .video = .{
            .get_properties_fn = get_properties,
            .flush_fn = flush,
        },
    },
},

framebuffer: [256_000]Color align(ashet.memory.page_size),
device: std.fs.File,

pub fn init(
    file_name: []const u8,
) error{ FileNotFound, BadFile, DeviceUnresponsive, IoError }!AVAPv1_Framebuffer {
    var fb: AVAPv1_Framebuffer = .{
        .framebuffer = @splat(.black),
        .device = undefined,
    };

    fb.device = std.fs.cwd().openFile(file_name, .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound,
        => return error.FileNotFound,

        error.BadPathName,
        error.IsDir,
        error.NoDevice,
        => return error.BadFile,

        error.SystemResources,
        error.WouldBlock,
        error.AccessDenied,
        error.ProcessNotFound,
        error.Unexpected,
        error.PermissionDenied,
        error.SharingViolation,
        error.PathAlreadyExists,
        error.PipeBusy,
        error.NameTooLong,
        error.InvalidUtf8,
        error.InvalidWtf8,
        error.NetworkNotFound,
        error.AntivirusInterference,
        error.SymLinkLoop,
        error.ProcessFdQuotaExceeded,
        error.SystemFdQuotaExceeded,
        error.FileTooBig,
        error.NoSpaceLeft,
        error.NotDir,
        error.DeviceBusy,
        error.FileLocksNotSupported,
        error.FileBusy,
        => return error.IoError,
    };
    errdefer fb.device.close();

    const ack = ping(fb.device) catch |err| switch (err) {
        error.InputOutput,
        error.SystemResources,
        error.IsDir,
        error.OperationAborted,
        error.BrokenPipe,
        error.ConnectionResetByPeer,
        error.ConnectionTimedOut,
        error.NotOpenForReading,
        error.SocketNotConnected,
        error.WouldBlock,
        error.Canceled,
        error.AccessDenied,
        error.ProcessNotFound,
        error.LockViolation,
        error.Unexpected,
        error.PermissionDenied,
        error.Overflow,
        error.NoDevice,
        error.FileTooBig,
        error.NoSpaceLeft,
        error.DeviceBusy,
        error.DiskQuota,
        error.InvalidArgument,
        error.NotOpenForWriting,
        error.MessageTooBig,
        => return error.IoError,

        error.Timeout,
        => return error.DeviceUnresponsive,
    };
    if (!ack) {
        logger.err("device did not respond to ping", .{});
        return error.DeviceUnresponsive;
    }

    ashet.video.load_splash_screen(.{
        .base = &fb.framebuffer,
        .width = 640,
        .height = 400,
        .stride = 640,
    });

    fb.flush_with_error() catch |err| switch (err) {
        error.InputOutput,
        error.SystemResources,
        error.IsDir,
        error.OperationAborted,
        error.BrokenPipe,
        error.ConnectionResetByPeer,
        error.ConnectionTimedOut,
        error.NotOpenForReading,
        error.SocketNotConnected,
        error.WouldBlock,
        error.Canceled,
        error.AccessDenied,
        error.ProcessNotFound,
        error.LockViolation,
        error.Unexpected,
        error.PermissionDenied,
        error.Overflow,
        error.NoDevice,
        error.FileTooBig,
        error.NoSpaceLeft,
        error.DeviceBusy,
        error.DiskQuota,
        error.InvalidArgument,
        error.NotOpenForWriting,
        error.MessageTooBig,
        => return error.IoError,

        error.Timeout,
        => return error.DeviceUnresponsive,

        error.WriteBufferFailed => {
            logger.err("write buffers failed", .{});
            return error.DeviceUnresponsive;
        },

        error.SwapBuffersFailed => {
            logger.err("swap buffers failed", .{});
            return error.DeviceUnresponsive;
        },
    };

    return fb;
}

fn get_properties(driver: *Driver) ashet.video.DeviceProperties {
    const vd = driver.resolve(AVAPv1_Framebuffer, "driver");
    return .{
        .video_memory = &vd.framebuffer,
        .video_memory_mapping = .buffered,
        .stride = width,
        .resolution = .{
            .width = width,
            .height = height,
        },
    };
}

fn flush(driver: *Driver) void {
    const vd = driver.resolve(AVAPv1_Framebuffer, "driver");

    vd.flush_with_error() catch |err| {
        logger.err("video driver failure: {t}", .{err});
    };
}

fn flush_with_error(vd: *AVAPv1_Framebuffer) !void {
    logger.debug("write buffer", .{});
    try write_buffer(vd.device, 0, @ptrCast(&vd.framebuffer));

    logger.debug("swap buffers", .{});
    try swap_buffers(vd.device);
}

fn ping(port: std.fs.File) !bool {
    try write_command(port, .ping, "");

    const deadline: Deadline = .from_ms(100);

    const header = try read_header(port, deadline);
    try read_discarding(port, header.length, deadline, .log);
    try read_footer(port, header, deadline);

    return header.ack;
}

pub fn write_buffer(port: std.fs.File, offset: u32, buffer: []const u8) !void {
    const length: u32 = std.math.cast(u32, buffer.len +| 4) orelse return error.Overflow;

    try write_header(port, length, .write_buffer);

    try write_all(port, std.mem.asBytes(&std.mem.nativeToLittle(u32, offset)));
    try write_all(port, buffer);

    try write_footer(port, length);

    const deadline: Deadline = .from_ms(100);

    const header = try read_header(port, deadline);
    try read_discarding(port, header.length, deadline, .log);
    try read_footer(port, header, deadline);

    if (header.ack == false)
        return error.WriteBufferFailed;
}

pub fn swap_buffers(port: std.fs.File) !void {
    try write_command(port, .swap_buffer, "");

    const deadline: Deadline = .from_ms(100);

    const header = try read_header(port, deadline);
    try read_discarding(port, header.length, deadline, .log);
    try read_footer(port, header, deadline);

    if (header.ack == false)
        return error.SwapBuffersFailed;
}

fn write_command(port: std.fs.File, cmd: Command, buffer: []const u8) !void {
    try write_header(port, buffer.len, cmd);
    if (buffer.len > 0) {
        try write_all(port, buffer);
    }
    try write_footer(port, buffer.len);
}

const Command = enum(u7) {
    ping = 0,
    write_buffer = 1,
    swap_buffer = 2,
    update_palette = 3,
    await_vblank = 4,
    write_rectangle = 5,
};
const Header = packed struct(u32) {
    length: u24,
    cmd: Command,
    ack: bool,
};

fn write_header(port: std.fs.File, length: usize, cmd: Command) !void {
    const enc = Header{
        .length = std.math.cast(u24, length) orelse return error.Overflow,
        .cmd = cmd,
        .ack = false,
    };

    var cmd_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &cmd_buf, @bitCast(enc), .little);
    try write_all(port, &cmd_buf);
}

fn write_footer(port: std.fs.File, total_length: usize) !void {
    const overhead = compute_padding(total_length);
    if (overhead > 0) {
        const padding: [4]u8 = @splat(0);
        try write_all(port, padding[0..overhead]);
    }
}

fn read_header(port: std.fs.File, deadline: Deadline) !Header {
    var buffer: [4]u8 = undefined;
    try read_all(port, &buffer, deadline);
    return @bitCast(std.mem.readInt(u32, &buffer, .little));
}

fn read_footer(port: std.fs.File, response: Header, deadline: Deadline) !void {
    const overhead = compute_padding(response.length);
    try read_discarding(port, overhead, deadline, .ignore);
}

fn read_discarding(port: std.fs.File, length: usize, deadline: Deadline, output: enum { ignore, log }) !void {
    var buffer: [8192]u8 = undefined;

    var count: usize = 0;
    while (count < length) {
        try deadline.check();

        const limit = @min(buffer.len, length - count);
        const len = try port.read(buffer[0..limit]);

        if (len > 0 and output == .log) {
            logger.err("unexpected data from device: {x}", .{buffer[0..len]});
        }

        count += len;
    }
}

fn compute_padding(total_length: usize) usize {
    const aligned = std.mem.alignForward(usize, total_length, 4);
    return aligned - total_length;
}

fn write_all(port: std.fs.File, buffer: []const u8) !void {
    // logger.debug("write {d} bytes", .{buffer.len});

    try port.writeAll(buffer);
}

fn read_all(port: std.fs.File, buffer: []u8, deadline: Deadline) !void {
    // logger.debug("read {d} bytes", .{buffer.len});

    var offset: usize = 0;
    while (offset < buffer.len) {
        try deadline.check();

        const len = try port.read(buffer[offset..]);

        // if (len > 0) {
        //     logger.debug(" .. {x}", .{buffer[offset .. offset + len]});
        // }

        offset += len;
    }
}

const Deadline = struct {
    pub const infinite: Deadline = .{ .end = null, .duration = 0 };

    start: ?std.time.Instant,
    duration: u64,

    pub fn from_ms(ms: u64) Deadline {
        return .{
            .start = std.time.Instant.now() catch @panic("unsupported system"),
            .duration = std.time.ns_per_ms * ms,
        };
    }

    pub fn check(deadline: Deadline) !void {
        const start = deadline.start orelse return;

        const now = std.time.Instant.now() catch unreachable;
        if (now.since(start) >= deadline.duration)
            return error.Timeout;
    }
};
