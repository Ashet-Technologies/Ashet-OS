const std = @import("std");

/// A utility which destructures a span of text into a sequence of words, splitting
/// at word boundaries and ignoring whitespace characters inbetween.
///
/// Control characters are also ignored.
const WordScanner = @This();

text: []const u8,
pos: usize = 0,

pub fn init(text: []const u8) WordScanner {
    return .{ .text = text };
}

pub fn next(ws: *WordScanner) ?[]const u8 {
    const word, _, _ = ws.next_with_space() orelse return null;
    return word;
}

pub fn next_with_space(ws: *WordScanner) ?struct { []const u8, bool, bool } {
    ws.skip_whitespace();

    const len = ws.text.len;
    if (ws.pos >= len) {
        return null;
    }

    const head = ws.pos;

    var last: CharType = .whitespace;
    while (ws.peek()) |chr| {
        const class = classify_chr(chr);
        if (class == .whitespace)
            break;

        // A transition from punctuation back to word character
        // also introduces a word split.
        // This allows us to split "foo,bar" into "foo," and "bar"
        if (class == .word and last == .punctuation)
            break;

        ws.consume(chr);
        last = class;
    }

    const tail = ws.pos;

    const spc_before = if (head > 0)
        is_whitespace(ws.text[head - 1])
    else
        false;
    const spc_after = if (tail < ws.text.len)
        is_whitespace(ws.text[tail])
    else
        false;

    return .{ ws.text[head..tail], spc_before, spc_after };
}

fn skip_whitespace(ws: *WordScanner) void {
    while (ws.peek()) |chr| {
        if (!is_whitespace(chr))
            break;
        ws.consume(chr);
    }
}

fn peek(ws: *const WordScanner) ?u8 {
    if (ws.pos >= ws.text.len)
        return null;
    return ws.text[ws.pos];
}

/// Consumes the given (expected) character.
/// `chr` is just provided to prevent implementation mistakes.
fn consume(ws: *WordScanner, chr: u8) void {
    std.debug.assert(ws.pos < ws.text.len);
    std.debug.assert(ws.text[ws.pos] == chr);
    ws.pos += 1;
}

fn is_whitespace(chr: u8) bool {
    return switch (classify_chr(chr)) {
        .whitespace => true,
        .punctuation, .word => false,

        // We currently treat control characters as "ignorable whitespace":
        .control => true,
    };
}

const CharType = enum {
    /// Control characters
    control,

    /// Whitespace characters
    whitespace,

    /// Punctuation characters
    punctuation,

    /// Word characters. These are always part of a word body.
    word,
};

fn classify_chr(chr: u21) CharType {
    const cc = std.ascii.control_code;

    return switch (chr) {
        cc.nul,
        cc.soh,
        cc.stx,
        cc.etx,
        cc.eot,
        cc.enq,
        cc.ack,
        cc.bel,
        cc.bs,
        // cc.ht,
        // cc.lf,
        cc.vt,
        cc.ff,
        // cc.cr,
        cc.so,
        cc.si,
        cc.dle,
        cc.dc1,
        cc.dc2,
        cc.dc3,
        cc.dc4,
        cc.nak,
        cc.syn,
        cc.etb,
        cc.can,
        cc.em,
        cc.sub,
        cc.esc,
        cc.fs,
        cc.gs,
        cc.rs,
        cc.us,
        cc.del,
        => .control,

        cc.ht,
        cc.lf,
        cc.cr,
        ' ',
        => .whitespace,

        '!' => .punctuation,
        '"' => .punctuation,
        '#' => .punctuation,
        '$' => .punctuation,
        '%' => .punctuation,
        '&' => .punctuation,
        '\'' => .punctuation,
        '(' => .punctuation,
        ')' => .punctuation,
        '*' => .punctuation,
        '+' => .punctuation,
        ',' => .punctuation,
        '-' => .punctuation,
        '.' => .punctuation,
        '/' => .punctuation,
        ':' => .punctuation,
        ';' => .punctuation,
        '<' => .punctuation,
        '=' => .punctuation,
        '>' => .punctuation,
        '?' => .punctuation,
        '@' => .punctuation,
        '[' => .punctuation,
        '\\' => .punctuation,
        ']' => .punctuation,
        '^' => .punctuation,
        '_' => .punctuation,
        '`' => .punctuation,
        '{' => .punctuation,
        '|' => .punctuation,
        '}' => .punctuation,
        '~' => .punctuation,

        // non-breaking space,
        '\u{00A0}',
        => .word,

        // we default to "this is a word character" for now:
        else => .word,
    };
}

test WordScanner {
    const expected_sequence: []const []const u8 = &.{
        "Li",
        "Europan",
        "lingues",
        "es",
        "membres",
        "del", // whitespace must be a word separator
        "sam",
        "familie.",
        "Lor,", // a transition from non-word to word must be a boundary
        "separat",
        "existentie",
    };

    var scanner: WordScanner = .init(
        \\  Li Europan lingues es membres del
        \\sam familie. Lor,separat existentie 
    );

    for (expected_sequence) |expected| {
        try std.testing.expectEqualStrings(expected, scanner.next() orelse return error.NoLine);
    }
    try std.testing.expectEqual(null, scanner.next());
}
