// zig fmt: off
export fn @"ashet_{[name]s}"() callconv(.C) void {{
    const suffix =
        \\
        \\.section .ashet.strings
        \\2:
        \\  .ascii "{[name]s}"
        \\  .byte 0
    ;
    switch (target_arch) {{
        .thumb => asm volatile (
        // use the "interwork register" for temporarily loading the
        // true address:
            \\  ldr ip, 1f
            \\  blx ip
            // align word to to 4 so we have sane pointer semantics:
            \\  .align 2
            \\1:
            \\  .long 0xAA55BB66
            \\
            \\.section .ashet.patch
            \\  .long 0x01
            \\  .long 1b
            \\  .long 2f
            ++ suffix),
        .x86 => asm volatile (
            \\1:
            // Will be encoded as E9 78 56 34 12, so the patch address
            // is instruction "address + 1" which can be unaligned, as
            // x86 doesn't care at all:
            \\  jmp 0x12345678
            \\
            \\.section .ashet.patch
            \\  .long 0x01
            \\  .long 1b + 1
            \\  .long 2f
            ++ suffix),
        .riscv32 => asm volatile (
            // load from pc-relative address, then jump to loaded address
            \\  lw t0, 1f
            \\  jr t0
            \\  
            // align word to to 4 so we have sane pointer semantics:
            \\  .align 2
            \\1:
            \\  .long 0xAA55BB66
            \\
            \\.section .ashet.patch
            \\  .long 0x01
            \\  .long 1b
            \\  .long 2f
            ++ suffix),
    }}
}}
