const std = @import("std");
const ashet = @import("../main.zig");

pub const Service = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);

    system_resource: ashet.resources.SystemResource = .{ .type = .service },

    pub const destroy = Destructor.destroy;

    pub fn _internal_destroy(sock: *Service) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};
