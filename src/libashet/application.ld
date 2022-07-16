ENTRY(_start)
SECTIONS {

    . = 0x80800000;

    .text : {
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
