const std = @import("std");
const ashet = @import("../main.zig");

pub const Pipe = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .pipe },

    pub fn destroy(sock: *Pipe) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};
