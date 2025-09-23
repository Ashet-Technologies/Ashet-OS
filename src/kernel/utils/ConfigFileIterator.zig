//!
//! This iterator is meant for comptime iteration of line based
//! textual data.
//!
const std = @import("std");

const ConfigFileIterator = @This();

iter: std.mem.TokenIterator(u8, .any),

line_iter: std.mem.TokenIterator(u8, .any) = undefined,

pub fn init(str: []const u8) ConfigFileIterator {
    return .{
        .iter = std.mem.tokenizeAny(u8, str, "\r\n"),
    };
}

/// Yields a tokenizer which reads whitespace separated tokens from the next line.
/// If no line is present anymore, will yield `null`.
pub fn next(self: *ConfigFileIterator) ?*std.mem.TokenIterator(u8, .any) {
    while (self.iter.next()) |raw_line| {
        const trimmed_line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (trimmed_line.len == 0)
            continue;
        if (std.mem.startsWith(u8, trimmed_line, "#"))
            continue;
        self.line_iter = std.mem.tokenizeAny(u8, trimmed_line, " \t");
        return &self.line_iter;
    }
    return null;
}

test "ConfigFileIterator" {
    const expect = std.testing.expect;
    const expectEqualSlices = std.testing.expectEqualSlices;

    // Test case 1: Empty and whitespace-only input
    {
        const input =
            \\
            \\
            \\   
            \\
        ;
        var it = ConfigFileIterator.init(input);
        try expect(it.next() == null);
    }

    // Test case 2: Comments and empty lines
    {
        const input =
            \\# A comment
            \\
            \\  # another comment with leading whitespace
        ;
        var it = ConfigFileIterator.init(input);
        try expect(it.next() == null);
    }

    // Test case 3: Simple key-value pair
    {
        const input = "key value";
        var it = ConfigFileIterator.init(input);
        var line_it = it.next() orelse return error.TestUnexpectedNull;
        try expectEqualSlices(u8, "key", line_it.next().?);
        try expectEqualSlices(u8, "value", line_it.next().?);
        try expect(line_it.next() == null);
        try expect(it.next() == null);
    }

    // Test case 4: Multiple lines with mixed content
    {
        const input =
            \\# Config Start
            \\
            \\line1 token1 token2
            \\    line2 token3
            \\
            \\# Config End
        ;
        var it = ConfigFileIterator.init(input);

        var line1_it = it.next() orelse return error.TestUnexpectedNull;
        try expectEqualSlices(u8, "line1", line1_it.next().?);
        try expectEqualSlices(u8, "token1", line1_it.next().?);
        try expectEqualSlices(u8, "token2", line1_it.next().?);
        try expect(line1_it.next() == null);

        var line2_it = it.next() orelse return error.TestUnexpectedNull;
        try expectEqualSlices(u8, "line2", line2_it.next().?);
        try expectEqualSlices(u8, "token3", line2_it.next().?);
        try expect(line2_it.next() == null);

        try expect(it.next() == null);
    }

    // Test case 5: Different line endings
    {
        const input = "line1\r\nline2\rline3\n";
        var it = ConfigFileIterator.init(input);

        var line_it1 = it.next() orelse return error.TestUnexpectedNull;
        try expectEqualSlices(u8, "line1", line_it1.next().?);
        try expect(line_it1.next() == null);

        var line_it2 = it.next() orelse return error.TestUnexpectedNull;
        try expectEqualSlices(u8, "line2", line_it2.next().?);
        try expect(line_it2.next() == null);

        var line_it3 = it.next() orelse return error.TestUnexpectedNull;
        try expectEqualSlices(u8, "line3", line_it3.next().?);
        try expect(line_it3.next() == null);

        try expect(it.next() == null);
    }
}
