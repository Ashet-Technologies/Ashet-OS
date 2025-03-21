extern "lib" fn dyncall(a: u32, b: u32) void;

export fn _start() u32 {
    dyncall(10, 20);
    return 0;
}

export fn process_exit(a: u32, b: u32, c: u32, d: u32) void {
    _ = a;
    _ = b;
    _ = c;
    _ = d;
    asm volatile (
        \\
        // Use the "IP" register to perform our own syscall veneer.
        // This veneer loads the absolute syscall address from '.local' (which
        // will be patched by the operating system loader), then branches to it.
        \\  ldr ip, .syscall_address
        // Then, we just branch to the just loaded address, so invoke the syscall
        // as if it would've been called locally:
        \\  bx ip
        \\.align 2
        \\.syscall_address:
        \\  .long 0x11223344

        // Emit an entry in the '.ashet.syscall' section to
        // register this syscall.

        // This will not be contained in the final .ashex executable,
        // but will be converted into correct syscall locations.
        \\.section .ashet.syscall
        // Type of the syscall entry:
        \\  .long 0x1
        // Local application-relative address of the syscall:
        \\  .long .syscall_address
        // Index into the ashet string table:
        \\  .long .syscall_name
        //
        // Also create an entry in the ashet string table:
        \\.section .ashet.strings
        \\.syscall_name:
        \\  .long  .syscall_name_end - .syscall_name_start
        \\.syscall_name_start:
        \\  .ascii "process_exit"
        \\.syscall_name_end:
        \\  .byte 0
    );
}
