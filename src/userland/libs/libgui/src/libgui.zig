//!
//! This library contains shared code between the widget server,
//! the kernel, the gui editor and potentially also applications.
//!

const std = @import("std");

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

    pub fn vertical_alignment(anchor: Anchor) Alignment {
        return .from_anchor(anchor.left, anchor.right);
    }

    pub fn horizontal_alignment(anchor: Anchor) Alignment {
        return .from_anchor(anchor.top, anchor.bottom);
    }
};

/// Alignment implements the evaluation of an anchor-based placement.
pub const Alignment = enum {
    /// Aligns to the near edge of the frame.
    near,

    /// Aligns with the far edge of the frame.
    far,

    /// Aligns between the near and the far edge, keeping size.
    center,

    /// Aligns between the near and the far edge, keeping the margins to each edge.
    margin,

    pub fn from_anchor(near: bool, far: bool) Alignment {
        if (near) {
            return if (far) .margin else .near;
        } else {
            return if (far) .far else .center;
        }
    }

    pub const Bounds = struct {
        near_margin: i16,
        size: u16,
        far_margin: i16,
        limit: u16,
    };

    pub fn compute_pos(al: Alignment, bounds: Bounds) i16 {
        switch (al) {
            .near, .margin => return bounds.near_margin,
            .far => return @intCast(std.math.clamp(
                @as(i32, bounds.limit) -| bounds.far_margin -| bounds.size,
                std.math.minInt(i16),
                std.math.maxInt(i16),
            )),
            .center => @panic("no"),
        }
    }

    pub fn compute_size(al: Alignment, bounds: Bounds) u16 {
        switch (al) {
            .near, .far, .center => return bounds.size,
            .margin => {
                return @intCast(std.math.clamp(
                    @as(i32, bounds.limit) - bounds.near_margin - bounds.far_margin,
                    std.math.minInt(u16),
                    std.math.maxInt(u16),
                ));
            },
        }
    }
};
