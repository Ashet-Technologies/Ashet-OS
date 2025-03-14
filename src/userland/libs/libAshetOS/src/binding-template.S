
#define STR(x) #x
#define SSTR(x) STR(x)
#define CONCAT(a, b) a#b

#if defined(PLATFORM_THUMB)
.thumb_func
#endif

.global SYMBOL_NAME
.type SYMBOL_NAME, %function
SYMBOL_NAME:

#if defined(PLATFORM_THUMB)

    // use the "interwork register" for temporarily loading the
    // true address:
    ldr ip, .syscall_address
    bx ip

.align 2 // align word to to 4 so we have sane pointer semantics:
.syscall_address:
  .long 0xAA55BB66

#elif defined(PLATFORM_RISCV32)

    // load from pc-relative address, then jump to loaded address
    lw t0, .syscall_address
    jr t0

.align 2 // align word to to 4 so we have sane pointer semantics:
.syscall_address:
    .long 0xAA55BB66

#elif defined(PLATFORM_X86)

    // Will be encoded as [B8 DD CC BB AA], which we can patch
    // by changing the location (symbol name + 1)
    mov $0xAABBCCDD, %eax
    // Is encoded as [FF E0], and performs an absolute near jump.
    // Using %eax is fine for SysV-i386 ABI, as it's one of the caller-saved
    // registers.
    jmpl *%eax

.align 2 // align word to to 4 so we have sane pointer semantics:
.set .syscall_address, SYMBOL_NAME + 1

#else
    #error "Unsupported Platform!"
#endif

// Emit a patch into the ".ashet.patch" section.
//
// This will always be emitted when a symbol from this object file will be pulled in.
// This way, we always emit a patch if the syscall is referenced.
//
// Otherwise, this object file is skipped
.section .ashet.patch
    .long 0x01              // .type
    .long .syscall_address  // .offset
    .long .syscall_name     // .name_ptr

// We need to recognize the syscall by name, so we also
// have to emit a string into the strings section:
.section .ashet.strings
.syscall_name:
  .asciz SSTR(SYSCALL_NAME)


