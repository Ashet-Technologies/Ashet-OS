const std = @import("std");
const ashet = @import("../main.zig");

pub const Window = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .window },

    pub fn destroy(sock: *Window) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};
pub const Desktop = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .desktop },

    pub fn destroy(sock: *Desktop) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};

pub const Widget = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .widget },

    pub fn destroy(sock: *Widget) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};

pub const WidgetType = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .widget_type },

    pub fn destroy(sock: *WidgetType) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};
