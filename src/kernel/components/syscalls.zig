const std = @import("std");
const hal = @import("hal");
const ashet = @import("../main.zig");

const abi = ashet.abi;

const ashet_syscall_interface: abi.SysCallInterface align(16) = .{
    .console = .{
        .clear = @"console.clear",
        .print = @"console.print",
        .output = @"console.output",
        .setCursor = @"input.setCursor",
        .readLine = @"input.readLine",
    },
    .video = .{
        .setMode = @"video.setMode",
        .setBorder = @"video.setBorder",
        .setResolution = @"video.setResolution",
        .getVideoMemory = @"video.getVideoMemory",
        .getPaletteMemory = @"video.getPaletteMemory",
    },
    .process = .{
        .yield = @"process.yield",
        .exit = @"process.exit",
    },
    .fs = .{
        .delete = @"fs.delete",
        .mkdir = @"fs.mkdir",
        .rename = @"fs.rename",
        .stat = @"fs.stat",
        .openFile = @"fs.openFile",
        .read = @"fs.read",
        .write = @"fs.write",
        .seekTo = @"fs.seekTo",
        .flush = @"fs.flush",
        .close = @"fs.close",
        .openDir = @"fs.openDir",
        .nextFile = @"fs.nextFile",
        .closeDir = @"fs.closeDir",
    },
    .input = .{
        .getEvent = @"input.getEvent",
        .getKeyboardEvent = @"input.getKeyboardEvent",
        .getMouseEvent = @"input.getMouseEvent",
    },
};

pub fn initialize() void {
    //
}

pub fn getInterfacePointer() *align(16) const abi.SysCallInterface {
    return &ashet_syscall_interface;
}

fn @"console.clear"() callconv(.C) void {
    ashet.console.clear();
}

fn @"console.print"(ptr: [*]const u8, len: usize) callconv(.C) void {
    ashet.console.write(ptr[0..len]);
}
fn @"console.output"(ptr: [*]const u8, len: usize) callconv(.C) void {
    for (ptr[0..len]) |c| {
        ashet.console.putRaw(c);
    }
}

fn @"video.setMode"(mode: abi.VideoMode) callconv(.C) void {
    ashet.video.setMode(mode);
}
fn @"video.setBorder"(color: abi.ColorIndex) callconv(.C) void {
    ashet.video.setBorder(color);
}
fn @"video.getVideoMemory"() callconv(.C) [*]abi.ColorIndex {
    return ashet.video.memory.ptr;
}
fn @"video.getPaletteMemory"() callconv(.C) *[abi.palette_size]u16 {
    return ashet.video.palette;
}
fn @"video.setResolution"(w: u16, h: u16) callconv(.C) void {
    if (w == 0 or h == 0 or w > 400 or h > 300)
        return;
    ashet.video.setResolution(w, h);
}

fn @"process.exit"(exit_code: u32) callconv(.C) noreturn {
    ashet.scheduler.exit(exit_code);
}

fn @"process.yield"() callconv(.C) void {
    ashet.scheduler.yield();
}

fn @"fs.delete"(path_ptr: [*]const u8, path_len: usize) callconv(.C) bool {
    _ = path_len;
    _ = path_ptr;
    return false;
}

fn @"fs.mkdir"(path_ptr: [*]const u8, path_len: usize) callconv(.C) bool {
    _ = path_len;
    _ = path_ptr;
    return false;
}

fn @"fs.rename"(old_path_ptr: [*]const u8, old_path_len: usize, new_path_ptr: [*]const u8, new_path_len: usize) callconv(.C) bool {
    _ = old_path_len;
    _ = old_path_ptr;
    _ = new_path_len;
    _ = new_path_ptr;
    return false;
}

fn @"fs.stat"(path_ptr: [*]const u8, path_len: usize, info: *abi.FileInfo) callconv(.C) bool {
    info.* = ashet.filesystem.stat(path_ptr[0..path_len]) catch return false;
    return true;
}

fn @"fs.openFile"(path_ptr: [*]const u8, path_len: usize, access: abi.FileAccess, mode: abi.FileMode) callconv(.C) abi.FileHandle {
    return ashet.filesystem.open(path_ptr[0..path_len], access, mode) catch .invalid;
}

fn @"fs.read"(handle: abi.FileHandle, ptr: [*]u8, len: usize) callconv(.C) usize {
    return ashet.filesystem.read(handle, ptr[0..len]) catch 0;
}
fn @"fs.write"(handle: abi.FileHandle, ptr: [*]const u8, len: usize) callconv(.C) usize {
    return ashet.filesystem.write(handle, ptr[0..len]) catch 0;
}

fn @"fs.seekTo"(handle: abi.FileHandle, offset: u64) callconv(.C) bool {
    ashet.filesystem.seekTo(handle, offset) catch return false;
    return true;
}

fn @"fs.flush"(handle: abi.FileHandle) callconv(.C) bool {
    ashet.filesystem.flush(handle) catch return false;
    return true;
}
fn @"fs.close"(handle: abi.FileHandle) callconv(.C) void {
    ashet.filesystem.close(handle);
}

fn @"fs.openDir"(path_ptr: [*]const u8, path_len: usize) callconv(.C) abi.DirectoryHandle {
    return ashet.filesystem.openDir(path_ptr[0..path_len]) catch .invalid;
}
fn @"fs.nextFile"(handle: abi.DirectoryHandle, info: *abi.FileInfo) callconv(.C) bool {
    if (ashet.filesystem.next(handle) catch return false) |file| {
        info.* = file;
        return true;
    } else {
        info.* = undefined;
        return false;
    }
}
fn @"fs.closeDir"(handle: abi.DirectoryHandle) callconv(.C) void {
    ashet.filesystem.closeDir(handle);
}

fn @"input.getEvent"(event: *abi.InputEvent) callconv(.C) abi.InputEventType {
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
    event.* = ashet.input.getKeyboardEvent() orelse return false;
    return true;
}
fn @"input.getMouseEvent"(event: *abi.MouseEvent) callconv(.C) bool {
    event.* = ashet.input.getMouseEvent() orelse return false;
    return true;
}

fn @"input.setCursor"(x: u8, y: u8) callconv(.C) void {
    ashet.console.cursor.x = std.math.clamp(x, 0, ashet.console.width - 1);
    ashet.console.cursor.y = std.math.clamp(y, 0, ashet.console.height - 1);
}

fn @"input.readLine"(params: *abi.ReadLineParams) callconv(.C) abi.ReadLineResult {
    const res = ashet.console.readLine(params.buffer[0..params.buffer_len], params.width) catch |e| return switch (e) {
        error.Cancelled => .cancelled,
        else => return .failed,
    };

    std.debug.assert(res.len <= params.buffer_len);
    params.buffer_len = res.len;

    return .ok;
}
