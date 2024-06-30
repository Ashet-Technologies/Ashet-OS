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

    . = ALIGN(4096);
    
   __kernel_flash_end = . ;

    .data ALIGN(4096) : {
        . = ALIGN(4096);
        kernel_stack_start = .;
        . += 0x30000;
        kernel_stack = .;

        __kernel_data_start = .;
        . = ALIGN(4096);
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        . = ALIGN(4096);
        __kernel_data_end = .;
    }

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
    }
}