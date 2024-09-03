const std = @import("std");
const ashet = @import("../main.zig");

pub const Pipe = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);
    system_resource: ashet.resources.SystemResource = .{ .type = .pipe },

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(sock: *Pipe) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};
