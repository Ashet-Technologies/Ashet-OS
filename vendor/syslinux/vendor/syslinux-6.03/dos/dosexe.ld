/*
 * Linker script for an MS-DOS EXE binary; this hard-codes a simple
 * MZ header without relocations.
 *
 * For documentation on the MS-DOS MZ EXE format, see:
 * http://www.delorie.com/djgpp/doc/exe/
 */


/* Script for -z combreloc: combine and sort reloc sections */
OUTPUT_FORMAT("elf32-i386", "elf32-i386",
	      "elf32-i386")
OUTPUT_ARCH(i386)
EXTERN(_start)
ENTRY(_start)

SECTIONS
{
	. = 0;
	/* EXE header, from header.S */
	.header : {
		*(.header)
	} =0

	. = ALIGN(16);
	__header_size = .;
	__payload_lma = .;

	. = 0x100000000 - syslinux_size;
	.payload : AT (__payload_lma) {
		 __payload_start = .;
		 *(.payload)
		 __payload_end = .;
	}
	__payload_len = ABSOLUTE(__payload_end) - ABSOLUTE(__payload_start);
	__payload_dwords = __payload_len >> 2;

	__dgroup_lma = __payload_lma + syslinux_size;
	__payload_sseg = (__payload_lma - __dgroup_lma) >> 4;
	_exe_text_seg  = (__dgroup_lma - __header_size) >> 4;

/*
 *	__assert1 = ASSERT((__payload_len == syslinux_ldlinux_size),
 *	"syslinux_size must equal the size of .payload");
 */
	. = 0;
	__null = .;
	.null : AT(__dgroup_lma) {
		*(.null)
	}

	. = ALIGN(16);
	__text_vma = .;
	.text : AT (__text_vma + __dgroup_lma) {
		*(.text .stub .text.* .gnu.linkonce.t.*)
		*(.gnu.warning)
	} =0x90909090
	_etext = .;

	. = ALIGN(16);
	__rodata_vma = .;
	.rodata : AT (__rodata_vma + __dgroup_lma) {
		*(.rodata .rodata.* .gnu.linkonce.r.*)
	}

	/* Adjust the address for the data segment.  Avoid mixing code and
	   data within same 128-byte chunk. */
	. = ALIGN(128);
	__data_vma = .;
	.data : AT (__data_vma + __dgroup_lma) {
		*(.data .data.* .gnu.linkonce.d.*)
		SORT(CONSTRUCTORS)
	}
	.data1 : { *(.data1) }
	_edata = .;

	_exe_edata_low    = ((_edata + __dgroup_lma) & 511);
	_exe_edata_blocks = ((_edata + __dgroup_lma) + 511) >> 9;

	.bss (NOLOAD) : {
		__bss_start = .;
		*(.dynbss)
		*(.bss .bss.* .gnu.linkonce.b.*)
		*(COMMON)
		__bss_end = .;
	}

	. = ALIGN(16);
	.heap (NOLOAD) : {
		__heap_start = .;
		*(.heap)
		__heap_end = .;
	}

	. = ALIGN(16);
	.stack (NOLOAD) : {
		__stack_start = .;
		*(.stack)
		__stack_end = .;
	}
	. = ALIGN(16);
	_end = .;

	_exe_bss_paras = (_end - __bss_start) >> 4;


  /* Stabs debugging sections.  */
  .stab          0 : { *(.stab) }
  .stabstr       0 : { *(.stabstr) }
  .stab.excl     0 : { *(.stab.excl) }
  .stab.exclstr  0 : { *(.stab.exclstr) }
  .stab.index    0 : { *(.stab.index) }
  .stab.indexstr 0 : { *(.stab.indexstr) }
  .comment       0 : { *(.comment) }
  /* DWARF debug sections.
     Symbols in the DWARF debugging sections are relative to the beginning
     of the section so we begin them at 0.  */
  /* DWARF 1 */
  .debug          0 : { *(.debug) }
  .line           0 : { *(.line) }
  /* GNU DWARF 1 extensions */
  .debug_srcinfo  0 : { *(.debug_srcinfo) }
  .debug_sfnames  0 : { *(.debug_sfnames) }
  /* DWARF 1.1 and DWARF 2 */
  .debug_aranges  0 : { *(.debug_aranges) }
  .debug_pubnames 0 : { *(.debug_pubnames) }
  /* DWARF 2 */
  .debug_info     0 : { *(.debug_info .gnu.linkonce.wi.*) }
  .debug_abbrev   0 : { *(.debug_abbrev) }
  .debug_line     0 : { *(.debug_line) }
  .debug_frame    0 : { *(.debug_frame) }
  .debug_str      0 : { *(.debug_str) }
  .debug_loc      0 : { *(.debug_loc) }
  .debug_macinfo  0 : { *(.debug_macinfo) }
  /* SGI/MIPS DWARF 2 extensions */
  .debug_weaknames 0 : { *(.debug_weaknames) }
  .debug_funcnames 0 : { *(.debug_funcnames) }
  .debug_typenames 0 : { *(.debug_typenames) }
  .debug_varnames  0 : { *(.debug_varnames) }
  /DISCARD/ : { *(.note.GNU-stack) }
}
