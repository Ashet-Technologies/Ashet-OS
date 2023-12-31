MEMORY
{
           flash  (RX) : ORIGIN = 0x20000000, LENGTH = 32M
            dram (RWX) : ORIGIN = 0x80000000, LENGTH = 16M
    platform_ram (RWX) : ORIGIN = 0x81000000, LENGTH = 16M
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
        kernel_stack_start = .;
        . += 0x8000; 
        kernel_stack = .;
    } > dram

    .data : AT (__kernel_flash_end){
        __kernel_data_start = .;

        *(.data)
        *(.data.*)

        *(.sdata)
        *(.sdata.*)

        . = ALIGN(4);
        __kernel_data_end = .;
    } > dram

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

    __machine_linmem_end = ORIGIN(dram) + LENGTH(dram);

    .platform (NOLOAD) : {
        *(.platform)
        *(.platform.*)
    } > platform_ram

}
