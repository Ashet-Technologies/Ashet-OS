

.section .text.research

.global main
main:

    // > FROM: "SYSTEM V APPLICATION BINARY INTERFACE", Page: 37
    // > Registers %ebp, %ebx, %edi, %esi, and %esp "belong" to the calling function.
    // so we can safely use %eax here:

    mov $_farloc, %eax
    jmp *%eax


_farloc_ptr:
    .long _farloc

    // ljmp *_farloc
    ljmp $0x00,$_farloc

_farloc:
    push hello_msg
    mov hello_msg, %eax
    call puts

    push 0
    call exit

.section .rodata
hello_msg:
    .asciz "Hello, World!\n"
