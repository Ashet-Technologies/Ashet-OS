pub const TB_CLOCK: u64 = 40_500_000;

pub inline fn readLower() u32 {
    return asm volatile ("mftb %[value]"
        : [value] "=r" (-> u32),
    );
}

pub inline fn read() u64 {
    while (true) {
        const upper_before = asm volatile ("mftbu %[value]"
            : [value] "=r" (-> u32),
        );
        const lower = asm volatile ("mftb %[value]"
            : [value] "=r" (-> u32),
        );
        const upper_after = asm volatile ("mftbu %[value]"
            : [value] "=r" (-> u32),
        );
        if (upper_before == upper_after) {
            return (@as(u64, upper_after) << 32) | lower;
        }
    }
}
