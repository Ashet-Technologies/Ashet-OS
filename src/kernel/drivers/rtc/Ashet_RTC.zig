const std = @import("std");
const ashet = @import("../../main.zig");
const Driver = ashet.drivers.Driver;
const machine = ashet.machine.peripherals;

const Ashet_RTC = @This();

driver: Driver = .{
    .name = "Ashet RTC",
    .class = .{
        .rtc = .{
            .nanoTimestampFn = nanoTimestamp,
        },
    },
},
peri: *volatile machine.Timer,

pub fn init(peri: *volatile machine.Timer) Ashet_RTC {
    return .{
        .peri = peri,
    };
}

fn nanoTimestamp(driver: *Driver) i128 {
    const rtc: *Ashet_RTC = @alignCast(@fieldParentPtr("driver", driver));
    return rtc.peri.read_rtc() * @as(i128, std.time.ns_per_s);
}
