const std = @import("std");
const ashet = @import("../main.zig");

const video = ashet.video;

pub const Location = struct {
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

pub fn write(string: []const u8) void {
    for (string) |char| {
        put(char);
    }
}

pub fn put(char: u8) void {
    switch (char) {
        '\r' => cursor.x = 0,
        '\n' => newline(),
        else => putRaw(char),
    }
}

pub fn putRaw(char: u8) void {
    video.memory[charOffset(cursor.x, cursor.y)] = char;
    video.memory[attrOffset(cursor.x, cursor.y)] = attributes(fg, bg);

    cursor.x += 1;
    if (cursor.x >= width) {
        cursor.x = 0;
        newline();
    }
}

fn newline() void {
    cursor.y += 1;
    if (cursor.y >= height) {
        cursor.y -= 1;

        std.mem.copy(
            u8,
            video.memory[0..],
            video.memory[charOffset(0, 1)..charOffset(0, height)],
        );
        std.mem.set(
            u16,
            std.mem.bytesAsSlice(u16, video.memory[charOffset(0, height - 1)..charOffset(0, height)]),
            ' ' | (@as(u16, attributes(fg, bg)) << 8),
        );
    }
}

fn charOffset(x: u8, y: u8) usize {
    return 2 * (@as(usize, y) * width + @as(usize, x));
}

fn attrOffset(x: u8, y: u8) usize {
    return charOffset(x, y) + 1;
}

fn writeForWriter(_: void, string: []const u8) Error!usize {
    write(string);
    return string.len;
}

const Error = error{};

pub const Writer = std.io.Writer(void, Error, writeForWriter);

pub fn writer() Writer {
    return Writer{ .context = {} };
}
