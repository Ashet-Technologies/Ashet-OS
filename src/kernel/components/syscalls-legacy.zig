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
const builtin = @import("builtin");
const ashet = @import("../main.zig");

const abi = ashet.abi;

comptime {
    // Check if all syscalls are defined well:
    for (@typeInfo(ashet.abi.syscalls).Struct.decls) |decl| {
        const FType = @TypeOf(@field(ashet.abi.syscalls, decl.name));
        const compat_check: *const FType = @field(impls, decl.name);
        _ = compat_check;
        // @compileLog(FType, compat_check);
    }

    // Check if no stale code is left over:
    for (@typeInfo(impls).Struct.decls) |decl| {
        std.debug.assert(@hasDecl(ashet.abi.syscalls, decl.name));
    }
}

fn videoExclusiveWarning() noreturn {
    std.log.warn("process {*} does not have exclusive control over ", .{getCurrentProcess()});
    ashet.scheduler.exit(1);
}

pub fn initialize() void {
    // might require some work in the future for arm/x86
}

pub fn getCurrentThread() *ashet.scheduler.Thread {
    return ashet.scheduler.Thread.current() orelse @panic("syscall only legal in a process");
}

pub fn getCurrentProcess() *ashet.multi_tasking.Process {
    return if (getCurrentThread().process_link) |link|
        link.data.process
    else
        @panic("syscall only legal in a process");
}

const impls = struct {
    export fn @"ashet.video.acquire"() callconv(.C) bool {
        if (ashet.multi_tasking.exclusive_video_controller == null) {
            ashet.multi_tasking.exclusive_video_controller = getCurrentProcess();
            return true;
        } else {
            return false;
        }
    }

    export fn @"ashet.video.release"() callconv(.C) void {
        if (getCurrentProcess().isExclusiveVideoController()) {
            ashet.multi_tasking.exclusive_video_controller = null;
        }
    }

    export fn @"ashet.video.setBorder"(color: abi.ColorIndex) callconv(.C) void {
        if (!getCurrentProcess().isExclusiveVideoController()) {
            videoExclusiveWarning();
        }
        ashet.video.setBorder(color);
    }

    export fn @"ashet.video.getVideoMemory"() callconv(.C) [*]align(4) abi.ColorIndex {
        if (!getCurrentProcess().isExclusiveVideoController()) {
            videoExclusiveWarning();
        }
        return ashet.video.getVideoMemory().ptr;
    }

    export fn @"ashet.video.getPaletteMemory"() callconv(.C) *[abi.palette_size]abi.Color {
        if (!getCurrentProcess().isExclusiveVideoController()) {
            videoExclusiveWarning();
        }
        return ashet.video.getPaletteMemory();
    }

    export fn @"ashet.video.getPalette"(outpal: *[abi.palette_size]abi.Color) callconv(.C) void {
        const palmem = ashet.video.getPaletteMemory();
        outpal.* = palmem.*;
    }

    export fn @"ashet.video.setResolution"(w: u16, h: u16) callconv(.C) void {
        if (!getCurrentProcess().isExclusiveVideoController()) {
            videoExclusiveWarning();
        }
        if (w == 0 or h == 0)
            return;

        ashet.video.setResolution(
            @as(u15, @intCast(@min(std.math.maxInt(u15), w))),
            @as(u15, @intCast(@min(std.math.maxInt(u15), h))),
        );
    }

    export fn @"ashet.video.getMaxResolution"() callconv(.C) abi.Size {
        return ashet.video.getMaxResolution();
    }

    export fn @"ashet.video.getResolution"() callconv(.C) abi.Size {
        return ashet.video.getResolution();
    }

    export fn @"ashet.process.getBaseAddress"() callconv(.C) usize {
        return if (getCurrentProcess().executable_memory) |mem|
            @intFromPtr(mem.ptr)
        else
            0;
    }

    export fn @"ashet.ui.createWindow"(title: [*]const u8, title_len: usize, min: abi.Size, max: abi.Size, startup: abi.Size, flags: abi.CreateWindowFlags) callconv(.C) ?*const abi.Window {
        // const window = ashet.ui.Window.create(getCurrentProcess(), title[0..title_len], min, max, startup, flags) catch return null;
        // return &window.user_facing;
        _ = title;
        _ = title_len;
        _ = min;
        _ = max;
        _ = startup;
        _ = flags;
        return null;
    }

    export fn @"ashet.ui.destroyWindow"(win: *const abi.Window) callconv(.C) void {
        _ = win;
        // const window = ashet.ui.Window.getFromABI(win);
        // window.destroy();
    }

    export fn @"ashet.ui.moveWindow"(win: *const abi.Window, x: i16, y: i16) callconv(.C) void {
        _ = win;
        _ = x;
        _ = y;
        // const window = ashet.ui.Window.getFromABI(win);

        // window.user_facing.client_rectangle.x = x;
        // window.user_facing.client_rectangle.y = y;

        // window.pushEvent(.window_moved);
    }

    export fn @"ashet.ui.resizeWindow"(win: *const abi.Window, x: u16, y: u16) callconv(.C) void {
        _ = win;
        _ = x;
        _ = y;
        // const window = ashet.ui.Window.getFromABI(win);

        // window.user_facing.client_rectangle.width = x;
        // window.user_facing.client_rectangle.height = y;

        // window.pushEvent(.window_resized);
    }

    export fn @"ashet.ui.setWindowTitle"(win: *const abi.Window, title: [*]const u8, title_len: usize) callconv(.C) void {
        _ = win;
        _ = title;
        _ = title_len;
        // const window = ashet.ui.Window.getFromABI(win);
        // window.setTitle(title[0..title_len]) catch std.log.err("setWindowTitle: out of memory!", .{});
    }

    export fn @"ashet.ui.invalidate"(win: *const abi.Window, rect: abi.Rectangle) callconv(.C) void {
        _ = win;
        _ = rect;

        // const window = ashet.ui.Window.getFromABI(win);

        // const screen_rect = abi.Rectangle{
        //     .x = window.user_facing.client_rectangle.x + rect.x,
        //     .y = window.user_facing.client_rectangle.y + rect.y,
        //     .width = @intCast(std.math.clamp(rect.width, 0, @as(i17, window.user_facing.client_rectangle.width) - rect.x)),
        //     .height = @intCast(std.math.clamp(rect.height, 0, @as(i17, window.user_facing.client_rectangle.height) - rect.y)),
        // };

        // ashet.ui.invalidateRegion(screen_rect);
    }

    export fn @"ashet.network.udp.createSocket"(out: *abi.UdpSocket) callconv(.C) abi.udp.CreateError.Enum {
        out.* = ashet.network.udp.createSocket() catch |e| return abi.udp.CreateError.map(e);
        return .ok;
    }
    export fn @"ashet.network.udp.destroySocket"(sock: abi.UdpSocket) callconv(.C) void {
        ashet.network.udp.destroySocket(sock);
    }

    export fn @"ashet.network.tcp.createSocket"(out: *abi.TcpSocket) callconv(.C) abi.tcp.CreateError.Enum {
        out.* = ashet.network.tcp.createSocket() catch |e| return abi.tcp.CreateError.map(e);
        return .ok;
    }

    export fn @"ashet.network.tcp.destroySocket"(sock: abi.TcpSocket) callconv(.C) void {
        ashet.network.tcp.destroySocket(sock);
    }

    export fn @"ashet.fs.findFilesystem"(name_ptr: [*]const u8, name_len: usize) callconv(.C) abi.FileSystemId {
        if (ashet.filesystem.findFilesystem(name_ptr[0..name_len])) |fs| {
            std.debug.assert(fs != .invalid);
            return fs;
        } else {
            return .invalid;
        }
    }

    export fn @"ashet.ui.getSystemFont"(font_name_ptr: [*]const u8, font_name_len: usize, font_data_ptr: *[*]const u8, font_data_len: *usize) callconv(.C) abi.GetSystemFontError.Enum {
        _ = font_name_ptr;
        _ = font_name_len;
        _ = font_data_ptr;
        _ = font_data_len;
        return .ok;
        // const font_name = font_name_ptr[0..font_name_len];

        // const font_data = ashet.ui.getSystemFont(font_name) catch |err| {
        //     return abi.GetSystemFontError.map(err);
        // };

        // font_data_ptr.* = font_data.ptr;
        // font_data_len.* = font_data.len;

        // return .ok;
    }

};
