const ashet = @import("../../../main.zig");

pub const start = struct {
    //

    extern fn ashet_kernelMain() callconv(.C) noreturn;

    export fn _start() noreturn {
        // Force instantiation of vector table:
        _ = initial_vector_table;
        ashet_kernelMain();
    }

    pub const InterruptTable = extern struct {
        initial_stack_pointer: *anyopaque,
        reset: FunctionPointer,
        nmi: FunctionPointer,
        hard_fault: FunctionPointer,
        mem_manage: FunctionPointer,
        bus_fault: FunctionPointer,
        usage_fault: FunctionPointer,
        _reserved0: [4]u32,
        svcall: FunctionPointer,
        debug_monitor: FunctionPointer,
        _reserved1: u32,
        pendsv: FunctionPointer,
        systick: FunctionPointer,
    };

    extern var __kernel_stack_end: anyopaque;

    pub const initial_vector_table: InterruptTable linksection(".text.vector_table") = .{
        .initial_stack_pointer = &__kernel_stack_end,
        .reset = ashet_kernelMain,
        .nmi = panic_handler("nmi"),
        .hard_fault = panic_handler("hard_fault"),
        .mem_manage = panic_handler("mem_manage"),
        .bus_fault = panic_handler("bus_fault"),
        .usage_fault = panic_handler("usage_fault"),
        ._reserved0 = undefined,
        .svcall = panic_handler("svcall"),
        .debug_monitor = panic_handler("debug_monitor"),
        ._reserved1 = undefined,
        .pendsv = panic_handler("pendsv"),
        .systick = panic_handler("systick"),
    };

    fn panic_handler(comptime msg: []const u8) FunctionPointer {
        return struct {
            fn do_panic() callconv(.C) noreturn {
                ashet.Debug.println("panic: {s}", .{msg});
                @panic(msg);
            }
        }.do_panic;
    }

    export fn hang() noreturn {
        while (true) {
            // burn cycles:
            asm volatile ("" ::: "memory");
        }
    }
};

pub const FunctionPointer = *const fn () callconv(.C) void;
