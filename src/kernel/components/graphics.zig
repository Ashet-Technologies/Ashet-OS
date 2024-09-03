const std = @import("std");
const ashet = @import("../main.zig");

pub const Framebuffer = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);
    system_resource: ashet.resources.SystemResource = .{ .type = .framebuffer },

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(sock: *Framebuffer) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};

pub const Font = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);
    system_resource: ashet.resources.SystemResource = .{ .type = .font },

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(sock: *Font) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};
