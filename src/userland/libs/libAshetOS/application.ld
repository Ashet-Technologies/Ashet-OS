ENTRY(_start)

SECTIONS {
    .text : {
        *(.text)
        *(.text.*)
    } 

    .rodata : {
        *(.rodata)
        *(.rodata.*)
        . = ALIGN(4096);
    } 

    . = ALIGN(4096);

    .data : {
        *(.sdata)
        *(.sdata.*)

        *(.data)
        *(.data.*)
    }

    . = ALIGN(4);

    .bss (NOLOAD) : {
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
    }
}
