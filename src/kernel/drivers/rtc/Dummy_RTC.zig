const ashet = @import("../../main.zig");
const Driver = ashet.drivers.Driver;

const Dummy_RTC = @This();

driver: Driver = .{
    .name = "Dummy RTC",
    .class = .{
        .rtc = .{
            .nanoTimestampFn = nanoTimestamp,
        },
    },
},
time: i128,

pub fn init(initial_time: i128) Dummy_RTC {
    return Dummy_RTC{
        .time = initial_time,
    };
}

fn nanoTimestamp(driver: *Driver) i128 {
    const rtc: *Dummy_RTC = @alignCast(@fieldParentPtr("driver", driver));
    return rtc.time;
}
