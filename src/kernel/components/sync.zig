const std = @import("std");
const ashet = @import("../main.zig");

pub const Mutex = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);
    system_resource: ashet.resources.SystemResource = .{ .type = .mutex },

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(sock: *Mutex) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};

pub const SyncEvent = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);
    system_resource: ashet.resources.SystemResource = .{ .type = .sync_event },

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(sock: *SyncEvent) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};
