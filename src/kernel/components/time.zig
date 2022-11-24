const std = @import("std");
const hal = @import("hal");

pub const tz = "Europe/Berlin";

pub const tz_offset = 1 * std.time.ns_per_hour;

pub fn nanoTimestamp() i128 {
    return hal.time.nanoTimestamp() + tz_offset;
}
