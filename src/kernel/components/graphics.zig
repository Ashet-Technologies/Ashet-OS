const std = @import("std");
const ashet = @import("../main.zig");

pub const Framebuffer = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .framebuffer },

    pub fn destroy(sock: *Framebuffer) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};

pub const Font = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .font },

    pub fn destroy(sock: *Font) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};