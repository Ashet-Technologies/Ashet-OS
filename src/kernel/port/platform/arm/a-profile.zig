pub fn executing_isr() bool {
    @panic("not implemented yet!");
}

pub fn disable_interrupts() void {
    @panic("not implemented yet!");
}

pub fn enable_interrupts() void {
    @panic("not implemented yet!");
}

pub fn are_interrupts_enabled() bool {
    @panic("not implemented yet!");
}

pub const start = struct {
    export fn _arm_except_Undef() callconv(.C) noreturn {
        @panic("Undefined Instruction");
    }

    export fn _arm_except_SVC() callconv(.C) noreturn {
        @panic("Supervisor Call (SVC)");
    }

    export fn _arm_except_PrefAbort() callconv(.C) noreturn {
        @panic("Prefetch Abort");
    }

    export fn _arm_except_DataAbort() callconv(.C) noreturn {
        @panic("Data Abort");
    }

    export fn _arm_except_IRQ() callconv(.C) noreturn {
        @panic("Interrupt (IRQ)");
    }

    export fn _arm_except_FIQ() callconv(.C) noreturn {
        @panic("Fast Interrupt (FIQ)");
    }

    comptime {
        asm (
            \\.section .text._start
            \\
            // \\.global arm_vector_table
            \\.arm
            \\.type arm_exception_table, %function
            \\.global arm_exception_table
            \\arm_exception_table:
            //  Offset  Handler
            //  ===============
            //  00      Reset
            \\  ldr pc, =_start
            //  04      Undefined Instruction
            \\  ldr pc, =_arm_except_Undef
            //  08      Supervisor Call (SVC)
            \\  ldr pc, =_arm_except_SVC
            //  0C      Prefetch Abort
            \\  ldr pc, =_arm_except_PrefAbort
            //  10      Data Abort
            \\  ldr pc, =_arm_except_DataAbort
            //  14      (Reserved)
            \\  ldr pc, =hang
            //  18      Interrupt (IRQ)
            \\  ldr pc, =_arm_except_IRQ
            //  1C      Fast Interrupt (FIQ)
            \\  ldr pc, =_arm_except_FIQ
        );
        asm (
            \\.thumb
            \\.thumb_func
            \\.global _start
            \\.type _start, %function
            \\_start:
            \\  ldr r0, =__kernel_stack_end
            \\  mov sp, r0
            \\  bl ashet_kernelMain
            //  fallthrough to hang:
            \\
            // \\.thumb
            \\.thumb_func
            \\.global hang
            \\.type hang, %function
            \\hang:
            \\  b hang
            \\
            // \\.thumb
            // \\.thumb_func
            // \\.type _arm_except_Undef, %function
            // \\_arm_except_Undef:
            // \\  b hang
            // \\
            // \\.thumb
            // \\.thumb_func
            // \\.type _arm_except_SVC, %function
            // \\_arm_except_SVC:
            // \\  b hang
            // \\
            // \\.thumb
            // \\.thumb_func
            // \\.type _arm_except_PrefAbort, %function
            // \\_arm_except_PrefAbort:
            // \\  b hang
            // \\
            // \\.thumb
            // \\.thumb_func
            // \\.type _arm_except_DataAbort, %function
            // \\_arm_except_DataAbort:
            // \\  b hang
            // \\
            // \\.thumb
            // \\.thumb_func
            // \\.type _arm_except_IRQ, %function
            // \\_arm_except_IRQ:
            // \\  b hang
            // \\
            // \\.thumb
            // \\.thumb_func
            // \\.type _arm_except_FIQ, %function
            // \\_arm_except_FIQ:
            // \\  b hang
            // \\
            \\
            \\
        );
    }
};
