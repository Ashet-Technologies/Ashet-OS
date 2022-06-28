const std = @import("std");
const ashet = @import("../main.zig");

const video = ashet.video;

const Location = struct {
    x: u8,
    y: u8,
};

/// Width of the text console
pub const width = 64;

/// Height of the text console
pub const height = 32;

/// Current foreground color for newly characters
pub var fg: u4 = 0x00; // black

/// Current background color for newly characters
pub var bg: u4 = 0x0F; // white

pub var cursor: Location = .{ .x = 0, .y = 0 };

pub const attributes = video.charAttributes;

/// Sets a single character on the screen.
pub fn set(x: u8, y: u8, char: u8, attrs: u8) void {
    video.memory[charOffset(x, y)] = char;
    video.memory[attrOffset(x, y)] = attrs;
}

pub fn clear() void {
    cursor = .{ .x = 0, .y = 0 };
    std.mem.set(
        u16,
        std.mem.bytesAsSlice(u16, video.memory[0 .. 2 * width * height]),
        ' ' | (@as(u16, attributes(fg, bg)) << 8),
    );
}

fn charOffset(x: u8, y: u8) usize {
    return 2 * (@as(usize, y) * width + @as(usize, x));
}

fn attrOffset(x: u8, y: u8) usize {
    return charOffset(x, y) + 1;
}
