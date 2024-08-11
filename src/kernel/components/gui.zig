const std = @import("std");
const ashet = @import("../main.zig");

pub const Window = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .window },
};
pub const Desktop = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .desktop },
};

pub const Widget = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .widget },
};

pub const WidgetType = struct {
    system_resource: ashet.resources.SystemResource = .{ .type = .widget_type },
};
