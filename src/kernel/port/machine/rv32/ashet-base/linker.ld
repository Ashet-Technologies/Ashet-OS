MEMORY
{
           flash  (RX) : ORIGIN = 0x00000000, LENGTH = 32M
            dram (RWX) : ORIGIN = 0x80000000, LENGTH =  2M /* limited to keep us some space for the linear memory */
}

ENTRY(_start)
SECTIONS {
    . = ORIGIN(flash);

    __kernel_flash_start = .;

    .text : {
        *(.text._start)
        *(.text)
        *(.text.*)
    } > flash

    .rodata : {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata.*)
    } > flash

    . = ALIGN(4);

   __kernel_flash_end = . ;

    .stack (NOLOAD) : {
        . = ALIGN(4096);
        PROVIDE(__kernel_stack_start = .);
        . += 0x80000;  /* 512 kB of kernel stack? */
        PROVIDE(__kernel_stack_end = .);
    } > dram

    .data : {
        __kernel_data_start = .;

        *(.data)
        *(.data.*)

        *(.sdata)
        *(.sdata.*)

        . = ALIGN(4);
        __kernel_data_end = .;
    } > dram AT> flash

    .bss (NOLOAD) : {
        __kernel_bss_start = .;

        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)

        . = ALIGN(4);
        __kernel_bss_end = .;

        . = ALIGN(4096);

        __machine_linmem_start = .;
    } > dram

    __kernel_data_load = LOADADDR(.data);

    __kernel_ram_start = ORIGIN(dram);
}
