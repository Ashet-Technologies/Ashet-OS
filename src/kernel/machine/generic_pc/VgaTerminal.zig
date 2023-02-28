const std = @import("std");
const vga = @import("vga.zig");

const VgaTerminal = @This();

cursor_x: usize = 0,
cursor_y: usize = 0,

pub fn put(term: *VgaTerminal, c: u8) void {
    switch (c) {
        '\r' => {},
        '\n' => {
            term.cursor_x = 0;
            if (term.cursor_y == vga.text_height - 1) {
                term.scroll();
            } else {
                term.cursor_y += 1;
            }
        },
        else => {
            if (term.cursor_x == vga.text_width) {
                term.put('\n');
            }
            vga.text_base[term.cursor_y][term.cursor_x] = vga.Char{
                .char = c,
                .fg = .white,
                .bg = .black,
            };
            term.cursor_x += 1;
        },
    }
}

fn scroll(term: *VgaTerminal) void {
    _ = term;
    for (vga.text_base[1..vga.text_height], 0..) |line, y| {
        vga.text_base[y] = line;
    }
    for (vga.text_base[vga.text_height - 1]) |*c| {
        c.char = ' ';
    }
}

pub fn write(term: *VgaTerminal, msg: []const u8) void {
    for (msg) |c| {
        term.put(c);
    }
}

fn innerWrite(term: *VgaTerminal, msg: []const u8) Error!usize {
    term.write(msg);
    return msg.len;
}

const Error = error{};

pub const Writer = std.io.Writer(*VgaTerminal, Error, innerWrite);

pub fn writer(term: *VgaTerminal) Writer {
    return Writer{ .context = term };
}
