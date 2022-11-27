//!
//! This file implements or forwards all syscalls
//! that are available to applications.
//!
//! Each syscall is just declared as a function in that file and
//! will be collected by the `syscall_table` declaration.
//!
//! That declaration is then passed around for invoking the system.
//!
const std = @import("std");
const hal = @import("hal");
const ashet = @import("../main.zig");

const abi = ashet.abi;

pub const syscall_table: abi.SysCallTable = blk: {
    var table: abi.SysCallTable = undefined;
    for (abi.syscall_definitions) |def| {
        @field(table, def.name) = @as(def.signature, @field(@This(), def.name));
    }
    break :blk table;
};

pub fn initialize() void {
    // might require some work in the future for arm/x86
}

fn getCurrentThread() *ashet.scheduler.Thread {
    return ashet.scheduler.Thread.current() orelse @panic("syscall only legal in a process");
}

fn getCurrentProcess() *ashet.multi_tasking.Process {
    return getCurrentThread().process orelse @panic("syscall only legal in a process");
}

fn @"video.acquire"() callconv(.C) bool {
    if (ashet.multi_tasking.exclusive_video_controller == null) {
        ashet.multi_tasking.exclusive_video_controller = getCurrentProcess();
        return true;
    } else {
        return false;
    }
}

fn videoExclusiveWarning() noreturn {
    std.log.warn("process {*} does not have exclusive control over ", .{getCurrentProcess()});
    ashet.scheduler.exit(1);
}

fn @"video.release"() callconv(.C) void {
    if (getCurrentProcess().isExclusiveVideoController()) {
        ashet.multi_tasking.exclusive_video_controller = null;
    }
}

fn @"video.setMode"(mode: abi.VideoMode) callconv(.C) void {
    if (!getCurrentProcess().isExclusiveVideoController()) {
        return videoExclusiveWarning();
    }
    ashet.video.setMode(mode);
}
fn @"video.setBorder"(color: abi.ColorIndex) callconv(.C) void {
    if (!getCurrentProcess().isExclusiveVideoController()) {
        videoExclusiveWarning();
    }
    ashet.video.setBorder(color);
}
fn @"video.getVideoMemory"() callconv(.C) [*]align(4) abi.ColorIndex {
    if (!getCurrentProcess().isExclusiveVideoController()) {
        videoExclusiveWarning();
    }
    return ashet.video.memory.ptr;
}
fn @"video.getPaletteMemory"() callconv(.C) *[abi.palette_size]abi.Color {
    if (!getCurrentProcess().isExclusiveVideoController()) {
        videoExclusiveWarning();
    }
    return ashet.video.palette;
}
fn @"video.setResolution"(w: u16, h: u16) callconv(.C) void {
    if (!getCurrentProcess().isExclusiveVideoController()) {
        videoExclusiveWarning();
    }
    ashet.video.setResolution(
        std.math.min(w, 400),
        std.math.min(h, 300),
    );
}

fn @"process.exit"(exit_code: u32) callconv(.C) noreturn {
    ashet.scheduler.exit(exit_code);
}

fn @"process.yield"() callconv(.C) void {
    ashet.scheduler.yield();
}

fn @"process.getBaseAddress"() callconv(.C) usize {
    return getCurrentProcess().base_address;
}

fn @"process.breakpoint"() callconv(.C) void {
    const proc = getCurrentProcess();
    std.log.info("breakpoint in process {s}.", .{proc.master_thread.getName()});

    var cont: bool = false;
    while (!cont) {
        std.mem.doNotOptimizeAway(cont);
    }
}

fn @"fs.delete"(path_ptr: [*]const u8, path_len: usize) callconv(.C) abi.FileSystemError.Enum {
    _ = path_len;
    _ = path_ptr;
    std.log.err("fs.delete not implemented yet!", .{});
    return .ok;
}

fn @"fs.mkdir"(path_ptr: [*]const u8, path_len: usize) callconv(.C) abi.FileSystemError.Enum {
    _ = path_len;
    _ = path_ptr;
    std.log.err("fs.mkdir not implemented yet!", .{});
    return .ok;
}

fn @"fs.rename"(old_path_ptr: [*]const u8, old_path_len: usize, new_path_ptr: [*]const u8, new_path_len: usize) callconv(.C) abi.FileSystemError.Enum {
    _ = old_path_len;
    _ = old_path_ptr;
    _ = new_path_len;
    _ = new_path_ptr;
    std.log.err("fs.rename not implemented yet!", .{});
    return .ok;
}

fn @"fs.stat"(path_ptr: [*]const u8, path_len: usize, info: *abi.FileInfo) callconv(.C) abi.FileSystemError.Enum {
    info.* = ashet.filesystem.stat(path_ptr[0..path_len]) catch |e| return abi.FileSystemError.map(e);
    return .ok;
}

fn @"fs.openFile"(path_ptr: [*]const u8, path_len: usize, access: abi.FileAccess, mode: abi.FileMode, out: *abi.FileHandle) callconv(.C) abi.FileOpenError.Enum {
    out.* = ashet.filesystem.open(path_ptr[0..path_len], access, mode) catch |e| return abi.FileOpenError.map(e);
    return .ok;
}

fn @"fs.read"(handle: abi.FileHandle, ptr: [*]u8, len: usize, out: *usize) callconv(.C) abi.FileReadError.Enum {
    out.* = ashet.filesystem.read(handle, ptr[0..len]) catch |e| return abi.FileReadError.map(e);
    return .ok;
}
fn @"fs.write"(handle: abi.FileHandle, ptr: [*]const u8, len: usize, out: *usize) callconv(.C) abi.FileWriteError.Enum {
    out.* = ashet.filesystem.write(handle, ptr[0..len]) catch |e| return abi.FileWriteError.map(e);
    return .ok;
}

fn @"fs.seekTo"(handle: abi.FileHandle, offset: u64) callconv(.C) abi.FileSeekError.Enum {
    ashet.filesystem.seekTo(handle, offset) catch |e| return abi.FileSeekError.map(e);
    return .ok;
}

fn @"fs.flush"(handle: abi.FileHandle) callconv(.C) abi.FileWriteError.Enum {
    ashet.filesystem.flush(handle) catch |e| return abi.FileWriteError.map(e);
    return .ok;
}
fn @"fs.close"(handle: abi.FileHandle) callconv(.C) void {
    ashet.filesystem.close(handle);
}

fn @"fs.openDir"(path_ptr: [*]const u8, path_len: usize, out: *abi.DirectoryHandle) callconv(.C) abi.DirOpenError.Enum {
    out.* = ashet.filesystem.openDir(path_ptr[0..path_len]) catch |e| return abi.DirOpenError.map(e);
    return .ok;
}
fn @"fs.nextFile"(handle: abi.DirectoryHandle, info: *abi.FileInfo, eof: *bool) callconv(.C) abi.DirNextError.Enum {
    const entry_or_null = ashet.filesystem.next(handle) catch |e| return abi.DirNextError.map(e);
    info.* = entry_or_null orelse undefined;
    eof.* = (entry_or_null == null);
    return .ok;
}
fn @"fs.closeDir"(handle: abi.DirectoryHandle) callconv(.C) void {
    ashet.filesystem.closeDir(handle);
}

fn @"input.getEvent"(event: *abi.InputEvent) callconv(.C) abi.InputEventType {
    if (!getCurrentProcess().isExclusiveVideoController()) {
        return videoExclusiveWarning();
    }

    const evt = ashet.input.getEvent() orelse return .none;
    switch (evt) {
        .keyboard => |data| {
            event.* = .{ .keyboard = data };
            return .keyboard;
        },
        .mouse => |data| {
            event.* = .{ .mouse = data };
            return .mouse;
        },
    }
}

fn @"input.getKeyboardEvent"(event: *abi.KeyboardEvent) callconv(.C) bool {
    if (!getCurrentProcess().isExclusiveVideoController()) {
        return videoExclusiveWarning();
    }
    event.* = ashet.input.getKeyboardEvent() orelse return false;
    return true;
}

fn @"input.getMouseEvent"(event: *abi.MouseEvent) callconv(.C) bool {
    if (!getCurrentProcess().isExclusiveVideoController()) {
        return videoExclusiveWarning();
    }
    event.* = ashet.input.getMouseEvent() orelse return false;
    return true;
}

fn @"ui.createWindow"(title: [*]const u8, title_len: usize, min: abi.Size, max: abi.Size, startup: abi.Size, flags: abi.CreateWindowFlags) callconv(.C) ?*const abi.Window {
    const window = ashet.ui.Window.create(getCurrentProcess(), title[0..title_len], min, max, startup, flags) catch return null;
    return &window.user_facing;
}

fn getMutableWindow(win: *const abi.Window) *ashet.ui.Window {
    const window = @fieldParentPtr(ashet.ui.Window, "user_facing", win);
    return @intToPtr(*ashet.ui.Window, @ptrToInt(window));
}

fn @"ui.destroyWindow"(win: *const abi.Window) callconv(.C) void {
    const window = getMutableWindow(win);
    window.destroy();
}

fn @"ui.moveWindow"(win: *const abi.Window, x: i16, y: i16) callconv(.C) void {
    const window = getMutableWindow(win);

    window.user_facing.client_rectangle.x = x;
    window.user_facing.client_rectangle.y = y;

    window.pushEvent(.window_moved);
}

fn @"ui.resizeWindow"(win: *const abi.Window, x: u16, y: u16) callconv(.C) void {
    const window = getMutableWindow(win);

    window.user_facing.client_rectangle.width = x;
    window.user_facing.client_rectangle.height = y;

    window.pushEvent(.window_resized);
}

fn @"ui.setWindowTitle"(win: *const abi.Window, title: [*]const u8, title_len: usize) callconv(.C) void {
    const window = getMutableWindow(win);
    window.setTitle(title[0..title_len]) catch std.log.err("setWindowTitle: out of memory!", .{});
}

fn @"ui.pollEvent"(win: *const abi.Window, out: *abi.UiEvent) callconv(.C) abi.UiEventType {
    const window = getMutableWindow(win);

    const event = window.pullEvent() orelse return .none;
    switch (event) {
        .none => unreachable,
        .mouse => |val| out.* = .{ .mouse = val },
        .keyboard => |val| out.* = .{ .keyboard = val },
        .window_close, .window_minimize, .window_restore, .window_moving, .window_moved, .window_resizing, .window_resized => {},
    }
    return event;
}

fn @"ui.invalidate"(win: *const abi.Window, rect: abi.Rectangle) callconv(.C) void {
    const window = getMutableWindow(win);

    var screen_rect = abi.Rectangle{
        .x = window.user_facing.client_rectangle.x + rect.x,
        .y = window.user_facing.client_rectangle.y + rect.y,
        .width = @intCast(u16, std.math.clamp(rect.width, 0, @as(i17, window.user_facing.client_rectangle.width) - rect.x)),
        .height = @intCast(u16, std.math.clamp(rect.height, 0, @as(i17, window.user_facing.client_rectangle.height) - rect.y)),
    };

    ashet.ui.invalidateRegion(screen_rect);
}

const UdpError = abi.UdpError;
const TcpError = abi.TcpError;

fn @"network.udp.createSocket"(out: *abi.UdpSocket) callconv(.C) UdpError.Enum {
    out.* = ashet.network.udp.createSocket() catch |e| return abi.UdpError.map(e);
    return .ok;
}
fn @"network.udp.destroySocket"(sock: abi.UdpSocket) callconv(.C) void {
    ashet.network.udp.destroySocket(sock);
}
fn @"network.udp.bind"(sock: abi.UdpSocket, ep: abi.EndPoint) callconv(.C) UdpError.Enum {
    ashet.network.udp.bind(sock, ep) catch |e| return UdpError.map(e);
    return .ok;
}
fn @"network.udp.connect"(sock: abi.UdpSocket, ep: abi.EndPoint) callconv(.C) UdpError.Enum {
    ashet.network.udp.connect(sock, ep) catch |e| return UdpError.map(e);
    return .ok;
}
fn @"network.udp.disconnect"(sock: abi.UdpSocket) callconv(.C) UdpError.Enum {
    ashet.network.udp.disconnect(sock) catch |e| return UdpError.map(e);
    return .ok;
}
fn @"network.udp.send"(sock: abi.UdpSocket, data: [*]const u8, length: usize, result: *usize) callconv(.C) UdpError.Enum {
    result.* = ashet.network.udp.send(sock, data[0..length]) catch |e| return UdpError.map(e);
    return .ok;
}
fn @"network.udp.sendTo"(sock: abi.UdpSocket, receiver: abi.EndPoint, data: [*]const u8, length: usize, result: *usize) callconv(.C) UdpError.Enum {
    result.* = ashet.network.udp.sendTo(sock, receiver, data[0..length]) catch |e| return UdpError.map(e);
    return .ok;
}
fn @"network.udp.receive"(sock: abi.UdpSocket, data: [*]u8, length: usize, result: *usize) callconv(.C) UdpError.Enum {
    result.* = ashet.network.udp.receive(sock, data[0..length]) catch |e| return UdpError.map(e);
    return .ok;
}
fn @"network.udp.receiveFrom"(sock: abi.UdpSocket, sender: *abi.EndPoint, data: [*]u8, length: usize, result: *usize) callconv(.C) UdpError.Enum {
    result.* = ashet.network.udp.receiveFrom(sock, sender, data[0..length]) catch |e| return UdpError.map(e);
    return .ok;
}

fn @"time.nanoTimestamp"() callconv(.C) i128 {
    return ashet.time.nanoTimestamp();
}
