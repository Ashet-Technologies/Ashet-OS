const std = @import("std");

/// A utility which destructures a text into lines, split by `[<CR>] <LF>`.
///
/// It does not strip stray `<CR>` out of the text.
const LineScanner = @This();

const LF = '\n';
const CR = '\r';

text: []const u8,
pos: usize = 0,

pub fn init(text: []const u8) LineScanner {
    return .{ .text = text };
}

pub fn next(ls: *LineScanner) ?[]const u8 {
    const line, _ = ls.next_with_eol() orelse return null;
    return line;
}

pub fn next_with_eol(ls: *LineScanner) ?struct { []const u8, bool } {
    const len = ls.text.len;
    if (ls.pos >= len) {
        return null;
    }

    var cr_offset: usize = 1;
    const head = ls.pos;
    const tail = while (ls.pos < len) {
        if (ls.text[ls.pos] == LF) {
            // Decrement one past the line ending, otherwise we'll
            // see this line in the next round again:
            ls.pos += 1;
            break ls.pos - cr_offset;
        }
        // If we encounter a CR, we strip 1 byte
        // off if the next character is a LF, otherwise
        // we'll just keep the length as is.
        cr_offset = if (ls.text[ls.pos] == CR)
            2 // strip CR LF
        else
            1; // strip only LF
        ls.pos += 1;

        // the end of the text also counts as a line,
        // so we have to break with
    } else len;

    const eol = if (tail < ls.text.len)
        ls.text[tail] == LF
    else
        false;

    return .{ ls.text[head..tail], eol };
}

test LineScanner {
    var scanner: LineScanner = .init(
        \\Hello, World!
        \\  This is a second line
        \\And this is a line without terminator.
    );

    try std.testing.expectEqualStrings("Hello, World!", scanner.next() orelse return error.NoLine);
    try std.testing.expectEqualStrings("  This is a second line", scanner.next() orelse return error.NoLine);
    try std.testing.expectEqualStrings("And this is a line without terminator.", scanner.next() orelse return error.NoLine);
    try std.testing.expectEqual(null, scanner.next());
}

test "LineScanner empty string" {
    var scanner: LineScanner = .init("");
    try std.testing.expectEqual(null, scanner.next());
}

test "LineScanner single line" {
    const inputs: []const []const u8 = &.{
        "hello, world!",
        "hello, world!\n",
        "hello, world!\r\n",
    };

    for (inputs) |input| {
        var scanner: LineScanner = .init(input);
        try std.testing.expectEqualStrings("hello, world!", scanner.next() orelse return error.NoLine);
        try std.testing.expectEqual(null, scanner.next());
    }
}

test "LineScanner two lines" {
    const inputs: []const []const u8 = &.{
        "hello, world!\nchapter two",
        "hello, world!\nchapter two\n",
        "hello, world!\nchapter two\r\n",
        "hello, world!\r\nchapter two",
        "hello, world!\r\nchapter two\n",
        "hello, world!\r\nchapter two\r\n",
    };

    for (inputs) |input| {
        var scanner: LineScanner = .init(input);
        try std.testing.expectEqualStrings("hello, world!", scanner.next() orelse return error.NoLine);
        try std.testing.expectEqualStrings("chapter two", scanner.next() orelse return error.NoLine);
        try std.testing.expectEqual(null, scanner.next());
    }
}

test "LineScanner empty lines" {
    const input = "\n\n\n\r\n\n\r\n\r\n\n\n\r\n";
    var scanner: LineScanner = .init(input);

    for (0..10) |_| {
        try std.testing.expectEqualStrings("", scanner.next() orelse return error.NoLine);
    }
    try std.testing.expectEqual(null, scanner.next());
}
