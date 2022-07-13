const std = @import("std");
const hal = @import("hal");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.multitasking);

pub const Task = struct {
    screen_id: u4,
};
