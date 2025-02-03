

.section .text.research

.global main
main:

    // jmp _farloc
    jmp *_farloc_ptr

    jmp *(0xAABBCCDD)  # Indirect memory jump


_farloc_ptr:
    .long _farloc

    // ljmp *_farloc
    ljmp $0x00,$_farloc

_farloc:
    push _text

    call printf

    push 0
    call exit

.section .rodata
_text:
    .asciz "Hello, World!\n"
