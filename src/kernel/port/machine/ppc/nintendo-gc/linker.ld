
/*
 * Linkscript for GC
 *
 */

OUTPUT_FORMAT("elf32-powerpc", "elf32-powerpc", "elf32-powerpc");
OUTPUT_ARCH(powerpc:common);
EXTERN(_start);
ENTRY(_start);

PHDRS
{
  stub PT_LOAD FLAGS(5);
  text PT_LOAD FLAGS(5);
  data PT_LOAD FLAGS(6);
  bss  PT_LOAD;
}


/* MEMORY
{
    sram (RWX) : ORIGIN = 0x00000000, LENGTH = 32M
    dram (RWX) : ORIGIN = 0x80000000, LENGTH =  2M
} */

SECTIONS
{
    . = 0x80003100;

    __kernel_flash_start = .;

    /* Program */
    .init :
    {
        KEEP (*(.zgc_bootstrap))
        KEEP (*(.init))
    } :text = 0

    .text :
    {
        *(.text*)
    } :text = 0

    . = ALIGN(4096);

    .rodata :
    {
        *(.rodata*)
        *(.rodata1)
    } :data
    
    __kernel_flash_end = .;

    . = ALIGN(4096);

    .data :
    {
        __kernel_data_start = .;
        *(.data*)
        __sdata_start = .;
        *(.sdata) *(.sdata.*)
        __sdata2_start = .;
        *(.sdata2*)
        *(.data1)
        __kernel_data_end = .;
    }

    .eh_frame :
    {
        KEEP (*(.eh_frame))
    }

    .got :
    {
        *(.got*)
    }

    . = ALIGN(4096);

    .bss ALIGN(32) :
    {
        __kernel_bss_start = .;
        *(.sbss2*)
        *(.dynsbss)
        *(.sbss) *(.sbss.*)
        *(.scommon)
        . = ALIGN(4); /* Ensure section size is multiple of 4 bytes */
        *(.dynbss)
        *(.bss) *(.bss.*)
        *(COMMON)
        . = ALIGN(4096);
        __kernel_bss_end = .;
    } :bss

    . = ALIGN(4096);

    __kernel_stack_start = .;
    . += 0x20000;
    __kernel_stack_end = .;

    . = ALIGN(4096);

    __machine_linmem_start = .;
    __machine_linmem_end = 0x817FE000;

    __machine_linmem_length =  __machine_linmem_end - __machine_linmem_start;

    /*	DWARF debug sections.
        Symbols in the DWARF debugging sections are relative to the beginning
        of the section so we begin them at 0.  */
    /* DWARF 2 */
    .debug_info     0 : { *(.debug_info) }
    .debug_abbrev   0 : { *(.debug_abbrev) }
    .debug_str      0 : { *(.debug_str) }
    .debug_aranges  0 : { *(.debug_aranges) }
    .debug_line     0 : { *(.debug_line) }
    /* These must appear regardless of  .  */
}

