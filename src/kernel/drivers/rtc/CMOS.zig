const std = @import("std");
const ashet = @import("../../main.zig");
const Driver = ashet.drivers.Driver;
const x86 = @import("platform.x86");

const CMOS = @This();

driver: Driver = .{
    .name = "CMOS RTC",
    .class = .{
        .rtc = .{
            .nanoTimestampFn = nanoTimestamp,
        },
    },
},
disable_nmi: bool = false,

pub fn init() CMOS {
    return CMOS{};
}

const days_in_months = [_]u32{
    31, // jan
    28, // feb
    31, // mar
    30, // apr
    31, // may
    30, // jun
    31, // jul
    31, // aug
    30, // sep
    31, // oct
    30, // nov,
    31, // dez
};

const cumulated_days_in_months = blk: {
    var res: [12]u32 = undefined;
    res[0] = 0;
    for (1..res.len) |i| {
        res[i] = res[i - 1] + days_in_months[i - 1];
    }
    break :blk res;
};

fn nanoTimestamp(driver: *Driver) i128 {
    const rtc = @fieldParentPtr(CMOS, "driver", driver);

    const seconds = x86.cmos.readRegister(.seconds, rtc.disable_nmi);
    const minute = x86.cmos.readRegister(.minute, rtc.disable_nmi);
    const hour = x86.cmos.readRegister(.hour, rtc.disable_nmi);
    const month = x86.cmos.readRegister(.month, rtc.disable_nmi);
    const year_tenth = x86.cmos.readRegister(.year, rtc.disable_nmi);
    const century = x86.cmos.readRegister(.century, rtc.disable_nmi);

    const year = 100 * @as(u16, century.toInt()) + year_tenth.toInt();

    const years_to_epoc = year - std.time.epoch.epoch_year;

    const secs_to_start_of_day = @as(u32, hour.toInt()) + 60 * @as(u32, minute.toInt()) + 60 * 60 * @as(u32, minute.toInt());

    // std.log.info("month: {}", .{month.toInt()});

    const days_to_start_of_year = cumulated_days_in_months[month.toInt() - 1];

    // std.log.info("seconds = {}", .{seconds});
    // std.log.info("minute  = {}", .{minute});
    // std.log.info("hour    = {}", .{hour});
    // std.log.info("month   = {}", .{month});
    // std.log.info("year    = {}{}", .{ century, year });

    return std.time.ns_per_s * (std.time.epoch.secs_per_day * (356 * @as(i128, years_to_epoc) + days_to_start_of_year) + secs_to_start_of_day + seconds.toInt());
}
