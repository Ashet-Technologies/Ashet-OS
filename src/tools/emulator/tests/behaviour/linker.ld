ENTRY(_start)

SECTIONS {
    . = 0x00;

    .text : {
        *(.text*)
    }
    .rodata : {
        *(.rodata*)
    }
    
    . = 0x80000000;

    .data : {
        *(.data*)
    }
    
    .bss : {
        *(.bss*)
    }
}
