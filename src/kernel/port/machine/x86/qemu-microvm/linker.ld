ENTRY(_start)

SECTIONS
{
    . = 0x100000; /* load to 1 MB */

    __kernel_flash_start = .;

    .text : {
		    KEEP(*(.multiboot))
        *(.text)
        *(.text.*)
    }

    .rodata ALIGN(4096) : {
        *(.rodata)
        *(.rodata.*)
    }

   __kernel_flash_end = . ;

    .data ALIGN(4096) : {
        . = ALIGN(4096);
        __kernel_stack_start = .;
        . += 0x8000; 
        __kernel_stack_end = .;

        __kernel_data_start = .;
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        . = ALIGN(4);
        __kernel_data_end = .;
    }

    .bss ALIGN(4096) : {
        __kernel_bss_start = .;
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        . = ALIGN(4);
        __kernel_bss_end = .;
    }
}