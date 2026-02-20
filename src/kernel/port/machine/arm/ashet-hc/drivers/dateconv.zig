const std = @import("std");

pub const DateTime = struct {
    year: i32, // e.g. 2025 (must be >= 1)
    month: u8, // 1..12
    day: u8, // 1..31
    hour: u8, // 0..23
    minute: u8, // 0..59
    second: u8, // 0..59 (no leap seconds)

    /// parsed `2025-10-22T09:16:31`
    pub fn parse(text: *const [19]u8) !DateTime {
        if (text[4] != '-' or text[7] != '-' or text[10] != 'T' or text[7] != '-' or text[13] != ':' or text[16] != ':') {
            return error.InvalidCharacter;
        }
        return .{
            .year = try std.fmt.parseInt(i32, text[0..4], 10),
            .month = try std.fmt.parseInt(u8, text[5..7], 10),
            .day = try std.fmt.parseInt(u8, text[8..10], 10),
            .hour = try std.fmt.parseInt(u8, text[11..13], 10),
            .minute = try std.fmt.parseInt(u8, text[14..16], 10),
            .second = try std.fmt.parseInt(u8, text[17..19], 10),
        };
    }
};

pub const ConvertError = error{InvalidDate};

pub fn datetimeToUnix(dt: DateTime) ConvertError!i64 {
    // Basic validation
    if (dt.year < 1) return error.InvalidDate;
    if (dt.month < 1 or dt.month > 12) return error.InvalidDate;
    if (dt.hour > 23 or dt.minute > 59 or dt.second > 59) return error.InvalidDate;

    const dim_common = [_]u8{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var max_day: u8 = dim_common[dt.month];
    if (dt.month == 2 and isLeapYear(dt.year)) max_day = 29;
    if (dt.day < 1 or dt.day > max_day) return error.InvalidDate;

    const days: i64 = daysBeforeYear(dt.year) + daysBeforeMonthInYear(dt.year, dt.month) + dt.day - 1;

    const secs: i64 = days * 86_400 + @as(u32, dt.hour) * 3_600 + @as(i64, dt.minute) * 60 + @as(i64, dt.second);

    return secs;
}

fn isLeapYear(y: i32) bool {
    return (@mod(y, 4) == 0) and (@mod(y, 100) != 0) or (@mod(y, 400) == 0);
}

// Days from 1970-01-01 to the start of 'year' (supports years < 1970).
fn daysBeforeYear(year: i32) i64 {
    const y: i64 = year;
    if (year >= 1970) {
        const y1 = y - 1;
        const leaps_to_y1 = leapsUpTo(y1);
        const leaps_to_1969 = leapsUpTo(1969);
        return 365 * (y - 1970) + (leaps_to_y1 - leaps_to_1969);
    } else {
        // Days from year-01-01 up to 1969-12-31, then negate.
        const y1 = y - 1;
        const leaps_to_y1 = leapsUpTo(y1);
        const leaps_to_1969 = leapsUpTo(1969);
        const span = 365 * (1970 - y) + (leaps_to_1969 - leaps_to_y1);
        return -span;
    }
}

// Inclusive leap count up to year y (y >= 0).
fn leapsUpTo(y: i64) i64 {
    // Gregorian leap count formula with truncating division.
    return @divTrunc(y, 4) - @divTrunc(y, 100) + @divTrunc(y, 400);
}

// Days from the start of 'year' to the start of 'month' (1..12)
fn daysBeforeMonthInYear(year: i32, month: u8) i32 {
    const cum = [_]i32{
        0, // dummy for 0-index
        0, // Jan
        31, // Feb
        59, // Mar
        90, // Apr
        120, // May
        151, // Jun
        181, // Jul
        212, // Aug
        243, // Sep
        273, // Oct
        304, // Nov
        334, // Dec
    };
    var d = cum[month];
    if (month > 2 and isLeapYear(year)) d += 1; // add Feb 29
    return d;
}

test {
    const dt = try DateTime.parse("2025-10-22T09:16:31");
    try std.testing.expectEqual(2025, dt.year);
    try std.testing.expectEqual(10, dt.month);
    try std.testing.expectEqual(22, dt.day);
    try std.testing.expectEqual(9, dt.hour);
    try std.testing.expectEqual(16, dt.minute);
    try std.testing.expectEqual(31, dt.second);
}

test {
    const pairs = [_]struct { i64, DateTime }{
        .{ 1761136496, try .parse("2025-10-22T12:34:56") },
        .{ 1761117939, try .parse("2025-10-22T07:25:39") },
        .{ 1176111793, try .parse("2007-04-09T09:43:13") },
        .{ 1274111793, try .parse("2010-05-17T15:56:33") },
        .{ 747905400, try .parse("1993-09-13T07:30:00") },
    };

    for (pairs) |pair| {
        const timestamp, const datetime = pair;

        std.testing.expectEqual(timestamp, try datetimeToUnix(datetime)) catch |err| {
            std.log.err("datetime: {}", .{datetime});
            return err;
        };
    }
}
