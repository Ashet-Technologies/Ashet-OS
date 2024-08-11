const std = @import("std");
const ashet = @import("../main.zig");

pub const Mutex = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .mutex },
};

pub const SyncEvent = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .sync_event },
};
