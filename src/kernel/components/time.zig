const std = @import("std");
const hal = @import("hal");

pub const tz = "Europe/Berlin";

pub const tz_offset = 1 * std.time.ns_per_hour;

pub fn nanoTimestamp() i128 {
    return hal.time.nanoTimestamp() + tz_offset;
}

pub fn microTimestamp() i64 {
    return @intCast(i64, @divTrunc(nanoTimestamp(), std.time.ns_per_us));
}

pub fn milliTimestamp() i64 {
    return @intCast(i64, @divTrunc(nanoTimestamp(), std.time.ns_per_ms));
}

pub fn timestamp() i64 {
    return @divTrunc(milliTimestamp(), std.time.ms_per_s);
}
