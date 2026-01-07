const std = @import("std");
const ashet = @import("../../../../../main.zig");

const dateconv = @import("dateconv.zig");

const logger = std.log.scoped(.ds1307);

const machine = @import("../ashet-hc.zig");
const rp2350 = @import("rp2350");
const hal = @import("rp2350-hal");
const regz = rp2350.peripherals;

const Driver = ashet.drivers.Driver;

const DS1307_RTC = @This();

driver: Driver = .{
    .name = "DS1307",
    .class = .{
        .rtc = .{
            .nanoTimestampFn = nanoTimestamp,
        },
    },
},

time_base: i128,
ticks_base: u64,

pub fn init() !DS1307_RTC {
    const i2c = machine.hw_alloc.i2c.system_bus;

    // Select the backplane fabric I²C:
    try i2c.write_blocking(machine.hw_alloc.i2c_addresses.i2c_main_mux, &.{0x80}, null);

    // Select the first register in the RTC:
    try i2c.write_blocking(machine.hw_alloc.i2c_addresses.ds1307_rtc, &.{0x00}, null);

    var regs: RTC_Registers = undefined;
    try i2c.read_blocking(machine.hw_alloc.i2c_addresses.ds1307_rtc, std.mem.asBytes(&regs), null);

    if (regs.seconds.clock == .halted) {
        regs = .{
            .seconds = .{
                .seconds_bcd = 0x00,
                .clock = .running,
            },
            .minutes = 0x10,
            .hours = .{ .@"24h" = .{ .hour = 0x11 } },
            .day_of_week = 2,
            .date = 0x22,
            .month = 0x10,
            .year = 0x25,
            .control = .{
                .output_control = 0,
                .rate_select = .@"1Hz",
                .square_wave_enable = false,
            },
        };
        logger.warn("uninitialized rtc, resetting to {}", .{regs});

        // Select the first register in the RTC:
        try i2c.writev_blocking(machine.hw_alloc.i2c_addresses.ds1307_rtc, &.{
            &.{0x00},
            std.mem.asBytes(&regs),
        }, null);
    } else {
        logger.info("time from rtc: {}", .{regs});
    }

    const dt: dateconv.DateTime = .{
        .year = 2000 + @as(i32, regs.get_year()),
        .month = regs.get_month(),
        .day = regs.get_date(),
        .hour = regs.get_hours(),
        .minute = regs.get_minutes(),
        .second = regs.get_seconds(),
    };

    const unix_timestamp: i128 = dateconv.datetimeToUnix(dt) catch blk: {
        logger.err("failed to convert rtc time to posix timestamp: {}", .{regs});
        break :blk 1761124200;
    };

    return DS1307_RTC{
        .time_base = std.time.ns_per_s * unix_timestamp,
        .ticks_base = @intFromEnum(hal.time.get_time_since_boot()),
    };
}

fn nanoTimestamp(driver: *Driver) i128 {
    const rtc: *DS1307_RTC = @alignCast(@fieldParentPtr("driver", driver));

    const us_since_init: i128 = @intFromEnum(hal.time.get_time_since_boot()) - rtc.ticks_base;

    return rtc.time_base + std.time.ns_per_us * us_since_init;
}

const RTC_Registers = extern struct {
    const HourMode = enum(u1) { @"am/pm" = 0, @"24h" = 1 };
    seconds: packed struct(u8) {
        seconds_bcd: u7,
        clock: enum(u1) { running = 0, halted = 1 },
    },
    minutes: u8,
    hours: packed union {
        control: packed struct(u8) { @"opaque": u6, mode: HourMode, _reserved: u1 },
        @"am/pm": packed struct(u8) { hour: u5, half: enum(u1) { AM = 0, PM = 1 }, mode: HourMode = .@"am/pm", _reserved: u1 = 0 },
        @"24h": packed struct(u8) { hour: u6, mode: HourMode = .@"24h", _reserved: u1 = 0 },
    },
    day_of_week: u8,
    date: u8,
    month: u8,
    year: u8,
    control: packed struct(u8) {
        rate_select: enum(u2) {
            @"1Hz" = 0,
            @"4.096kHz" = 1,
            @"8.192kHz" = 2,
            @"32.768kHz" = 3,
        },
        _reserved0: u2 = 0,
        square_wave_enable: bool,
        _reserved1: u2 = 0,
        output_control: u1,
    },

    fn get_seconds(rtc: RTC_Registers) u8 {
        return bcd_to_dec(rtc.seconds.seconds_bcd);
    }

    fn get_minutes(rtc: RTC_Registers) u8 {
        return bcd_to_dec(rtc.minutes);
    }

    fn get_hours(rtc: RTC_Registers) u8 {
        return switch (rtc.hours.control.mode) {
            .@"24h" => bcd_to_dec(rtc.hours.@"24h".hour),
            .@"am/pm" => blk: {
                const hour_12 = bcd_to_dec(rtc.hours.@"am/pm".hour);
                break :blk switch (rtc.hours.@"am/pm".half) {
                    .AM => if (hour_12 == 12) 0 else hour_12,
                    .PM => if (hour_12 == 12) 12 else hour_12 + 12,
                };
            },
        };
    }

    fn get_date(rtc: RTC_Registers) u8 {
        return bcd_to_dec(rtc.date);
    }

    fn get_month(rtc: RTC_Registers) u8 {
        return bcd_to_dec(rtc.month);
    }

    fn get_year(rtc: RTC_Registers) u8 {
        return bcd_to_dec(rtc.year);
    }

    fn bcd_to_dec(bcd: u8) u8 {
        return 10 * (bcd >> 4) + (bcd & 0x0F);
    }

    pub const Format = enum { T, D, DT };
    pub fn fmt(regs: RTC_Registers, f: Format) RegFmt {
        return .{ .regs = regs, .format = f };
    }

    const RegFmt = struct {
        regs: RTC_Registers,
        fmt: Format,

        pub fn format(self: RegFmt, writer: *std.Io.Writer) !void {
            if (self.regs.seconds.clock == .halted) {
                try writer.writeAll("[STOPPED]");
                return;
            }

            if (self.fmt != .T) {
                try writer.print("{X:0>2}.{X:0>2}.20{X:0>2}/{d}", .{
                    self.regs.date,
                    self.regs.month,
                    self.regs.year,
                    self.regs.day_of_week,
                });
            }

            if (self.fmt != .D) {
                if (self.fmt != .T) {
                    try writer.writeAll(" ");
                }

                switch (self.regs.hours.control.mode) {
                    .@"24h" => try writer.print("{X:0>2}:{X:0>2}:{X:0>2}", .{
                        self.regs.hours.@"24h".hour,
                        self.regs.minutes,
                        self.regs.seconds.seconds_bcd,
                    }),
                    .@"am/pm" => try writer.print("{X:0>2} {s}:{X:0>2}:{X:0>2}", .{
                        self.regs.hours.@"am/pm".hour,
                        @tagName(self.regs.hours.@"am/pm".half),
                        self.regs.minutes,
                        self.regs.seconds.seconds_bcd,
                    }),
                }
            }

            if (self.fmt == .any) {
                try writer.print("; SWE={}; OUT={}; RS={s} ", .{
                    self.regs.control.square_wave_enable,
                    self.regs.control.output_control,
                    @tagName(self.regs.control.rate_select),
                });
            }
        }
    };

    pub fn format(regs: RTC_Registers, writer: *std.Io.Writer) !void {
        if (regs.seconds.clock == .halted) {
            try writer.writeAll("[STOPPED]");
            return;
        }

        try writer.print("{X:0>2}.{X:0>2}.20{X:0>2}/{d}", .{
            regs.date,
            regs.month,
            regs.year,
            regs.day_of_week,
        });

        try writer.writeAll(" ");

        switch (regs.hours.control.mode) {
            .@"24h" => try writer.print("{X:0>2}:{X:0>2}:{X:0>2}", .{
                regs.hours.@"24h".hour,
                regs.minutes,
                regs.seconds.seconds_bcd,
            }),
            .@"am/pm" => try writer.print("{X:0>2} {s}:{X:0>2}:{X:0>2}", .{
                regs.hours.@"am/pm".hour,
                @tagName(regs.hours.@"am/pm".half),
                regs.minutes,
                regs.seconds.seconds_bcd,
            }),
        }

        try writer.print("; SWE={}; OUT={}; RS={s} ", .{
            regs.control.square_wave_enable,
            regs.control.output_control,
            @tagName(regs.control.rate_select),
        });
    }
};
