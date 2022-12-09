const ashet = @import("../../main.zig");
const Driver = ashet.drivers.Driver;

const Goldfish = @This();

driver: Driver = .{
    .name = "Dummy RTC",
    .class = .{
        .rtc = .{
            .nanoTimestampFn = nanoTimestamp,
        },
    },
},
time: i128,

pub fn init(initial_time: i128) Goldfish {
    return Goldfish{
        .time = initial_time,
    };
}

fn nanoTimestamp(driver: *Driver) i128 {
    const rtc = @fieldParentPtr(Goldfish, "driver", driver);
    return rtc.time;
}
