/*
    Linker script for AshetOS applications.

    Documentation:
    - https://sourceware.org/binutils/docs/ld/Scripts.html
*/

ENTRY(_start)

PHDRS {
    readonly  PT_LOAD FILEHDR PHDRS FLAGS (5); /* RX!W */
    readwrite PT_LOAD               FLAGS (6); /* RW!X */
    dynamic   PT_DYNAMIC            FLAGS (4); /* R!W!X */
}

SECTIONS {
    . = SIZEOF_HEADERS;

    .dynsym : { *(.dynsym) } :readonly
    .dynstr : { *(.dynstr) } :readonly

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
        *(.igot.plt)
        *(.got)
        *(.igot)

        . = ALIGN(4096);
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
        
        . = ALIGN(4);
        *(.bss) *(.bss.*)

        . = ALIGN(4);
        *(.sbss) *(.sbss.*)

        . = ALIGN(4096);
    } :readwrite

    . = ALIGN(4096);

    /*
        Make the DYNAMIC program header last so we can quickly load and align 
        the actual data sections
     */
    .dynamic : { *(.dynamic) } :dynamic

    /* We're not a GNU system, even if we use GNU tools right now */
    /DISCARD/ : {
        *(.gnu.hash)
        *(.hash)
    }
}




    /* .plt            : { *(.plt) *(.iplt) }
    .plt.got        : { *(.plt.got) }
    .plt.sec        : { *(.plt.sec) }
    

 .rel.dyn        :
    {
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
    }
  .rel.plt        :
    {
      *(.rel.plt)
      *(.rel.iplt)
    }
  .relr.dyn : { *(.relr.dyn) } */