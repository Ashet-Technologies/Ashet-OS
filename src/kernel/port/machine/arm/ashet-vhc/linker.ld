MEMORY
{
    flash  (RX) : ORIGIN = 0x10000000, LENGTH = 16M
    psram (RWX) : ORIGIN = 0x11000000, LENGTH = 8M
    sram  (RWX) : ORIGIN = 0x20000000, LENGTH = 520K
}

ENTRY(_start)


__machine_linmem_start = ORIGIN(psram);
__machine_linmem_end   = ORIGIN(psram) + LENGTH(psram);

SECTIONS {
    . = ORIGIN(flash);

    __kernel_flash_start = .;

    .text : {
        KEEP(*(.text.vector_table*))
        *(.text*)
    } > flash

    .rodata : {
        . = ALIGN(4);
        *(.rodata*)
    } > flash

    . = ALIGN(4);

   __kernel_flash_end = . ;

    .stack (NOLOAD) : {
        . = ALIGN(4096);
        __kernel_stack_start = .;
        . += 0x40000; 
        __kernel_stack_end = .;
    } > sram

    .data : AT (__kernel_flash_end){
        __kernel_data_start = .;

        *(.data*)
        *(.sdata*)

        . = ALIGN(4);
        __kernel_data_end = .;
    } > sram

    .bss (NOLOAD) : {
        __kernel_bss_start = .;

        *(.bss*)
        *(.sbss*)

        . = ALIGN(4);
        __kernel_bss_end = .;

        . = ALIGN(4096);
    } > sram
}
