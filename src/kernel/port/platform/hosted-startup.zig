const std = @import("std");
const kernel = @import("kernel");

comptime {
    _ = kernel;
}

pub const std_options = kernel.std_options;

pub const panic = kernel.panic;

pub fn main() !void {
    kernel.ashet_kernelMain();
}

export fn hang() noreturn {
    std.debug.print("UNRECOVERABLE KERNEL CRASH, SYSTEM IS GOING TO DIE NOW!", .{});
    @breakpoint();
    while (true) {
        // burn cycles:
        asm volatile ("" ::: "memory");
    }
}
