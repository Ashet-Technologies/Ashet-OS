const std = @import("std");
const ashet = @import("../../main.zig");
const Driver = ashet.drivers.Driver;

const HostedSystemClock = @This();

driver: Driver = .{
    .name = "Host Clock",
    .class = .{
        .rtc = .{
            .nanoTimestampFn = nanoTimestamp,
        },
    },
},

pub fn init() HostedSystemClock {
    return .{};
}

fn nanoTimestamp(driver: *Driver) i128 {
    const rtc: *HostedSystemClock = @fieldParentPtr("driver", driver);
    _ = rtc;
    return std.time.nanoTimestamp();
}
