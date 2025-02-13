const std = @import("std");

pub fn freq(freq_hz: u64) FreqFormatter {
    return .{ .freq_hz = freq_hz };
}

pub const FreqFormatter = struct {
    const units = [_][]const u8{
        "Hz", // 1
        "kHz", // 4
        "MHz", // 7
        "GHz", // 10
    };

    freq_hz: u64,

    pub fn format(ff: FreqFormatter, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;

        var buffer: [std.math.log10_int(@as(u64, std.math.maxInt(u64))) + 2]u8 = undefined;

        const int_str = std.fmt.bufPrint(&buffer, "{d}", .{ff.freq_hz}) catch unreachable;

        const unit_index: usize = @min(units.len - 1, (int_str.len -| 1) / 3);

        const suffix_digits = 3 * unit_index;
        std.debug.assert(int_str.len > suffix_digits);

        const prefix = int_str[0 .. int_str.len - suffix_digits];
        const full_suffix = int_str[int_str.len - suffix_digits ..];
        const suffix = full_suffix[0..@min(full_suffix.len, options.precision orelse suffix_digits)];

        try writer.writeAll(prefix);
        if (suffix.len > 0) {
            try writer.writeAll(".");
            try writer.writeAll(suffix);
        }
        try writer.writeAll(" ");

        try writer.writeAll(units[unit_index]);
    }

    fn split(str: []const u8, digits: usize, prec: ?usize) struct { []const u8, []const u8 } {
        if (str.len < digits)
            return .{ "0", str[0 .. prec orelse str.len] };

        const head = str[0 .. str.len - digits];
        const full_tail = str[str.len - digits ..];
        const tail = if (prec) |p|
            full_tail[0..@min(p, full_tail.len)]
        else
            full_tail;
        return .{ head, tail };
    }
};

fn expect_fmt(expected: []const u8, comptime fmt: []const u8, args: anytype) !void {
    const actual = try std.fmt.allocPrint(std.testing.allocator, fmt, args);
    defer std.testing.allocator.free(actual);

    try std.testing.expectEqualStrings(expected, actual);
}

test freq {
    try expect_fmt("0 Hz", "{}", .{freq(0)});
    try expect_fmt("123 Hz", "{}", .{freq(123)});
    try expect_fmt("123.456 kHz", "{}", .{freq(123_456)});
    try expect_fmt("123.456789 MHz", "{}", .{freq(123_456_789)});
    try expect_fmt("123.456789101 GHz", "{}", .{freq(123_456_789_101)});

    try expect_fmt("0 Hz", "{:.2}", .{freq(0)});
    try expect_fmt("123 Hz", "{:.2}", .{freq(123)});
    try expect_fmt("123.45 kHz", "{:.2}", .{freq(123_456)});
    try expect_fmt("123.45 MHz", "{:.2}", .{freq(123_456_789)});
    try expect_fmt("123.45 GHz", "{:.2}", .{freq(123_456_789_101)});
}
