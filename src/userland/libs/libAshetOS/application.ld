/*
    Linker script for AshetOS applications.

    Documentation:
    - https://sourceware.org/binutils/docs/ld/Scripts.html
*/

ENTRY(_start)

PHDRS {
    readonly   PT_LOAD     FLAGS (0x00000005); /* RX!W */
    readwrite  PT_LOAD     FLAGS (0x00000006); /* RW!X */
    dynamic    PT_DYNAMIC  FLAGS (0x00000004); /* R!W!X */
    metadata   PT_LOAD     FLAGS (0x00100000); /* R!W!X */
}

SECTIONS {
    
    .text : {
        . = ALIGN(4);
        *(.text) *(.text.*)

        . = ALIGN(4);
        *(.rodata) *(.rodata.*)

        /*
            we can put the global offset table into the :readonly 
            header. This is okay because:
            - We do resolve *all* symbols on load
            - We apply memory protection *after* dynamic linking
            - We will never change the data afterwards
        */
        
        . = ALIGN(4);
        *(.got.plt)
        
        . = ALIGN(4);
        *(.igot.plt)
        
        . = ALIGN(4);
        *(.got)

        . = ALIGN(4);
        *(.igot)

    } :readonly

    /*
        we have to introduce a page-sized split between
        the :readonly and the :readwrite header so
        the page protection can properly separate them
     */
    . = ALIGN(4096);

    .data : {
        . = ALIGN(4);
        *(.sdata) *(.sdata.*)

        . = ALIGN(4);
        *(.data) *(.data.*)
    } :readwrite

    .bss : {
        . = ALIGN(4);
        *(.bss) *(.bss.*)

        . = ALIGN(4);
        *(.sbss) *(.sbss.*)
    } :readwrite

    . = ALIGN(4096);

    /*
        Make the DYNAMIC program header last so we can quickly load and align 
        the actual data sections
     */
    .dynamic : { *(.dynamic) } :dynamic
    
    /* . = ALIGN(4096); */

    .dynsym : { *(.dynsym) } :metadata
    .dynstr : { *(.dynstr) } :metadata

    .plt            : { *(.plt) *(.iplt) }  :metadata
    .plt.got        : { *(.plt.got) }  :metadata
    .plt.sec        : { *(.plt.sec) }  :metadata
    
    .rel.dyn : {
      *(.rel.init)
      *(.rel.text .rel.text.* .rel.gnu.linkonce.t.*)
      *(.rel.fini)
      *(.rel.rodata .rel.rodata.* .rel.gnu.linkonce.r.*)
      *(.rel.data.rel.ro .rel.data.rel.ro.* .rel.gnu.linkonce.d.rel.ro.*)
      *(.rel.data .rel.data.* .rel.gnu.linkonce.d.*)
      *(.rel.tdata .rel.tdata.* .rel.gnu.linkonce.td.*)
      *(.rel.tbss .rel.tbss.* .rel.gnu.linkonce.tb.*)
      *(.rel.ctors)
      *(.rel.dtors)
      *(.rel.got)
      *(.rel.bss .rel.bss.* .rel.gnu.linkonce.b.*)
      *(.rel.ifunc)
    } :metadata

    .rel.plt : {
      *(.rel.plt)
      *(.rel.iplt)
    } :metadata
    
    .relr.dyn : {
        *(.relr.dyn)
    } :metadata

    /* We're not a GNU system, even if we use GNU tools right now */
    /DISCARD/ : {
        *(.gnu.hash)
        *(.hash)
    }
}



