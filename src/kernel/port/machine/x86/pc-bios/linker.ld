ENTRY(_start)

MEMORY 
{
    memory (RWX) : ORIGIN = 0x100000, LENGTH = 512M
}

SECTIONS
{
    . = 0x100000; /* load to 1 MB */

    __kernel_flash_start = .;

    .text : {
	    KEEP(*(.text.multiboot*))
        *(.text)
        *(.text.*)
    } > memory 

    .rodata ALIGN(4096) : {
        *(.rodata)
        *(.rodata.*)
    } > memory 

    . = ALIGN(4096);
    
   __kernel_flash_end = . ;

    .data ALIGN(4096) : {
        . = ALIGN(4096);
        __kernel_stack_start = .;
        . += 0x30000;
        __kernel_stack_end = .;

        __kernel_data_start = .;
        . = ALIGN(4096);
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        . = ALIGN(4096);
        __kernel_data_end = .;
    } > memory 

    .bss ALIGN(4096) : {
        __kernel_bss_start = .;
        . = ALIGN(4096);
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        . = ALIGN(4096);
        __kernel_bss_end = .;

        . = ALIGN(4096);
        __machine_linmem_start = .;
        . += 0x01000000; /* 16 megs of RAM */
        . = ALIGN(4096);
        __machine_linmem_end = .;
    } > memory
}