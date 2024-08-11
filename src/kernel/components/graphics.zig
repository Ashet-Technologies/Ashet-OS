const std = @import("std");
const ashet = @import("../main.zig");

pub const Framebuffer = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .framebuffer },
};
