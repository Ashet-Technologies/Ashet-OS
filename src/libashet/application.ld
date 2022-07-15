ENTRY(_start)
SECTIONS {
    .text : {
        *(.text._start) /* moves _start to the load address, must be the first section */
        *(.text)
        *(.text.*)
    }

    . = ALIGN(4);

    .rodata : {
        *(.rodata)
        *(.rodata.*)
    }

    . = ALIGN(4);

    .data : {
        *(.data)
        *(.data.*)

        *(.sdata)
        *(.sdata.*)
    }

    . = ALIGN(4);

    .bss (NOLOAD) : {
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
    }
}
