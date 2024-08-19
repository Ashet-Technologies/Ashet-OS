const std = @import("std");
const ashet = @import("../main.zig");

pub const Service = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .service },

    pub fn destroy(sock: *Service) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};
