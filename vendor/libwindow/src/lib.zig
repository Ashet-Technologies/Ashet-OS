const std = @import("std");

pub const backends = struct {
    pub const x11 = @import("x11/x11.zig");
    pub const wayland = @import("wayland/wayland.zig");
    pub const win32 = @import("win32/win32.zig");
};

pub const Backend = enum {
    x11,
    wayland,
    win32,
};

pub const InitOptions = struct {
    backend: ?Backend = null,
};

pub fn init(options: InitOptions) !void {
    _ = options;
    try backends.x11.init();
}

pub fn deinit() void {
    //
}

pub fn pollEvent() !?Event {
    unreachable;
}

pub fn waitEvent() !Event {
    unreachable;
}

pub const Event = struct {
    data: union(enum) {
        //
    },
};

pub const Window = struct {
    pub const CreateOptions = struct {
        title: []const u8,
        size: Size,
    };

    pub fn create(options: CreateOptions) !*Window {
        _ = options;
        unreachable;
    }

    pub fn destroy(window: *Window) void {
        window.* = undefined;
    }
};

pub const Size = struct {
    width: i16,
    height: i16,

    pub fn new(x: i16, y: i16) Size {
        return .{ .width = x, .height = y };
    }
};
