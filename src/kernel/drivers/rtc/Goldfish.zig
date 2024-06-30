const ashet = @import("../../main.zig");
const Driver = ashet.drivers.Driver;

const Goldfish = @This();

driver: Driver = .{
    .name = "Goldfish RTC",
    .class = .{
        .rtc = .{
            .nanoTimestampFn = nanoTimestamp,
        },
    },
},
regs: *volatile Registers,

pub fn init(base: usize) Goldfish {
    return Goldfish{
        .regs = @ptrFromInt(base),
    };
}

fn nanoTimestamp(driver: *Driver) i128 {
    const rtc: *Goldfish = @fieldParentPtr("driver", driver);
    return rtc.regs.read();
}

const Registers = extern struct {
    time_low: u32, // 0x00           R: Get current time, then return low-order 32-bits.
    time_high: u32, // 0x04          R: Return high 32-bits, from previous TIME_LOW read.
    alarm_low: u32, // 0x08          W: Set low 32-bit value or alarm, then arm it.
    alarm_high: u32, // 0x0c         W: Set high 32-bit value of alarm.
    clear_interrupt: u32, // 0x10    W: Lower device's irq level.

    /// Values reported are still 64-bit nanoseconds, but they have a granularity
    /// of 1 second, and represent host-specific values (really 'time() * 1e9')
    pub fn read(self: *volatile Registers) u64 {
        const low = self.time_low;
        const high = self.time_high;
        return @as(u64, low) | (@as(u64, high) << 32);
    }
};
