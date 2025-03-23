const std = @import("std");
const ashet = @import("ashet-abi");

pub const Rectangle = ashet.Rectangle;
pub const Size = ashet.Size;
pub const Point = ashet.Point;
pub const Color = ashet.Color;

pub const Window = struct {
    design_size: Size = .new(400, 300),

    min_size: Size = .new(0, 0),
    max_size: Size = .new(std.math.maxInt(u16), std.math.maxInt(u16)),

    widgets: std.ArrayListUnmanaged(Widget) = .empty,
};

pub const Widget = struct {
    bounds: ashet.Rectangle,
    anchor: Anchor = .top_left,
    visible: bool = true,
    class: *const Class,
};

pub const Class = struct {
    pub const generic: Class = .{
        .name = "generic",
    };

    name: [:0]const u8,

    min_size: Size = .new(0, 0),
    max_size: Size = .new(std.math.maxInt(u16), std.math.maxInt(u16)),

    default_size: Size = .new(50, 40),
};

/// The anchor defines which side of a widget should stick to the parent boundary.
pub const Anchor = struct {
    pub const all: Anchor = .{ .top = true, .bottom = true, .left = true, .right = true };
    pub const top_left: Anchor = .{ .top = true, .bottom = false, .left = true, .right = false };
    pub const top_right: Anchor = .{ .top = true, .bottom = false, .left = false, .right = true };
    pub const bottom_left: Anchor = .{ .top = false, .bottom = true, .left = true, .right = false };
    pub const bottom_right: Anchor = .{ .top = false, .bottom = true, .left = false, .right = true };
    pub const none: Anchor = .{ .top = false, .bottom = false, .left = false, .right = false };

    top: bool,
    bottom: bool,
    left: bool,
    right: bool,
};
