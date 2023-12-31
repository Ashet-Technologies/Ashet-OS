const std = @import("std");

pub const Color = enum(u4) {
    black = 0,
    blue = 1,
    green = 2,
    cyan = 3,
    red = 4,
    magenta = 5,
    brown = 6,
    light_gray = 7,
    dim_gray = 8,
    light_blue = 9,
    light_green = 10,
    light_cyan = 11,
    light_red = 12,
    light_magenta = 13,
    yellow = 14,
    white = 15,
};

pub const Char = packed struct(u16) {
    char: u8,
    fg: Color,
    bg: Color,
};

pub const text_height = 80;
pub const text_width = 25;
pub const text_base = @as(*[text_height][text_width]Char, @ptrFromInt(0xB8000));
