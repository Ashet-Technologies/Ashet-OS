MEMORY
{
     flash  (RX) : ORIGIN = 0x20000000, LENGTH = 32M
      dram (RWX) : ORIGIN = 0x80000000, LENGTH = 16M
}

ENTRY(_start)
SECTIONS {

    .text : {
        *(.text)
        *(.text.*)
    } > flash

    .rodata : {
        *(.rodata)
        *(.rodata.*)
    } > flash

    .data : {
        *(.data)
        *(.data.*)
    } > dram

    .bss : {
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
    } > dram

    __kernel_end = .;
}
