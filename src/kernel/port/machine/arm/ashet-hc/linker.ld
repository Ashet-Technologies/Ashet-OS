MEMORY
{
    flash  (RX) : ORIGIN = 0x10000000, LENGTH = 16M
    psram (RWX) : ORIGIN = 0x11000000, LENGTH = 8M
    sram0  (RWX) : ORIGIN = 0x20000000, LENGTH = 256K - 0xB000 /* TODO: Fix this weirdness here when HSTX_DVI_2 driver is used */
    sram1  (RWX) : ORIGIN = 0x20035000, LENGTH = 256K + 0xB000
    sram2  (RWX) : ORIGIN = 0x20080000, LENGTH = 4K
    sram3  (RWX) : ORIGIN = 0x20081000, LENGTH = 4K
}

ENTRY(_start)


__machine_linmem_start = ORIGIN(psram);
__machine_linmem_end   = ORIGIN(psram) + LENGTH(psram);

SECTIONS {
    . = ORIGIN(flash);

    __kernel_flash_start = .;

    .text : {
        KEEP(*(.text.vector_table*))
        KEEP(*(.text.image_def*))
        *(.text*)
    } > flash

    .rodata : {
        . = ALIGN(4);
        *(.rodata*)
    } > flash

    .ARM.extab : {
        *(.ARM.extab* .gnu.linkonce.armextab.*)
    } > flash

    .ARM.exidx : {
        *(.ARM.exidx* .gnu.linkonce.armexidx.*)
    } > flash

    . = ALIGN(4);

   __kernel_flash_end = . ;

    .stack (NOLOAD) : {
        . = ALIGN(4096);
        __kernel_stack_start = .;
        . += 0x8000; 
        __kernel_stack_end = .;
    } > sram0

    .data : {
        __kernel_data_start = .;
        

        . = ALIGN(4);

        KEEP(*(.sram.bank0 .sram.bank0.*))
        
        *(.data*)
        . = ALIGN(4);
        
        *(.sdata*)
        . = ALIGN(4);
        

        . = ALIGN(4);
        __kernel_data_end = .;
    } > sram0 AT> flash

    .bss (NOLOAD) : {
        __kernel_bss_start = .;

        *(.bss*)
        *(.sbss*)

        . = ALIGN(4);
        __kernel_bss_end = .;

        . = ALIGN(4096);
    } > sram0


    .sram.bank1.noload (NOLOAD) :
    {
        KEEP(*(.sram.bank1.noload .sram.bank1.noload.*))
    } > sram1 AT> flash

    .sram.bank1 :
    {
        . = ALIGN(4);
        __rp2350_sram_bank1_start = .;
        KEEP(*(.sram.bank1 .sram.bank1.*))
        . = ALIGN(4);
        __rp2350_sram_bank1_end = .;
    } > sram1 AT> flash

    .sram.bank2 :
    {
        . = ALIGN(4);
        __rp2350_sram_bank2_start = .;
        KEEP(*(.sram.bank2 .sram.bank2.*))
        . = ALIGN(4);
        __rp2350_sram_bank2_end = .;
    } > sram2 AT> flash

    .sram.bank3 :
    {
        . = ALIGN(4);
        __rp2350_sram_bank3_start = .;
        KEEP(*(.sram.bank3 .sram.bank3.*))
        . = ALIGN(4);
        __rp2350_sram_bank3_end = .;
    } > sram3 AT> flash
    
    __kernel_data_load       = LOADADDR(.data);

    __rp2350_sram_bank1_load = LOADADDR(.sram.bank1);
    __rp2350_sram_bank2_load = LOADADDR(.sram.bank2);
    __rp2350_sram_bank3_load = LOADADDR(.sram.bank3);

    DISCARD : {
        *(.discard)
        *(.discard.*)
    }
}
