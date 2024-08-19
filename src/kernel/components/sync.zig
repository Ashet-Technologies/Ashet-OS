const std = @import("std");
const ashet = @import("../main.zig");

pub const Mutex = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .mutex },

    pub fn destroy(sock: *Mutex) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};

pub const SyncEvent = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .sync_event },

    pub fn destroy(sock: *SyncEvent) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};
