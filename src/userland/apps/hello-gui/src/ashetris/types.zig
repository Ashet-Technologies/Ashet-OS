const ashet = @import("ashet");
const consts = @import("consts.zig");

pub const Piece = struct {
    width: u8,
    height: u8,
    shape: [4][4]bool,

    pub fn left_coord(self: *const Piece, midpoint_x: i8) i8 {
        return midpoint_x - @as(i8, @intCast(self.width / 2));
    }

    pub fn top_coord(self: *const Piece, midpoint_y: i8) i8 {
        return midpoint_y - @as(i8, @intCast(self.height / 2));
    }
};

pub const Field = [consts.height][consts.width]u8;
