/* -----------------------------------------------------------------------
 *   
 *   Copyright 2008-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * Linker script for the SYSLINUX core
 */

OUTPUT_FORMAT("elf32-i386", "elf32-i386", "elf32-i386")
OUTPUT_ARCH(i386)
ENTRY(_start)

SECTIONS
{
	. = 0;
	ImageBase = .;		/* For gnu-efi's crt0 */
	__module_start = .;
	. = SEGMENT_START("text-segment", 0) + SIZEOF_HEADERS;
	.text : {
		FILL(0x90909090)
		__text_start = .;
		*(.text)
		*(.text.*)
		__text_end = .;
	}

	. = ALIGN(16);

	.rodata : {
		__rodata_start = .;
		*(.rodata)
		*(.rodata.*)
		__rodata_end = .;
	}

	. = ALIGN(4);

	.ctors : {
		__ctors_start = .;
		KEEP (*(SORT(.ctors.*)))
		KEEP (*(.ctors))
		__ctors_end = .;
	}

	.dtors : {
		__dtors_start = .;
		KEEP (*(SORT(.dtors.*)))
		KEEP (*(.dtors))
		__dtors_end = .;
	}

	. = ALIGN(4096);
	.rel : {
		*(.rel.got)
		*(.rel.data)
		*(.rel.data.*)
		*(.rel.ctors)
	}

	. = ALIGN(4);

	.gnu.hash : {
		__gnu_hash_start = .;
		*(.gnu.hash)
		__gnu_hash_end = .;
	}


	.dynsym : {
		__dynsym_start = .;
		*(.dynsym)
		__dynsym_end = .;
	}

	. = ALIGN(4);

	.dynstr : {
		__dynstr_start = .;
		*(.dynstr)
		__dynstr_end = .;
	}

	. = ALIGN(4);

	.dynlink : {
		__dynlink_start = .;
		*(.dynlink)
		__dynlink_end = .;
	}

	. = ALIGN(4);

	.got : {
		__got_start = .;
		KEEP (*(.got.plt))
		KEEP (*(.got))
		__got_end = .;
	}

	. = ALIGN(4);

	.dynamic : {
		__dynamic_start = .;
		*(.dynamic)
		__dynamic_end = .;
	}

	. = ALIGN(16);

	.data : {
		__data_start = .;
		*(.data)
		*(.data.*)
		*(.lowmem)
		__data_end = .;
	}

	.reloc : {
		*(.reloc)
	}

	.comment : {
		*(.commet)
	}

	.symtab : {
		*(.symtab)
	}

	.strtab : {
		*(.strtab)
	}

	.bss : {
		/* the EFI loader doesn't seem to like a .bss section,
		   so we stick it all into .data: */
		__bss_start = .;
		*(.bss)
		*(.bss.*)
		*(.bss16)
		*(.hugebss)
		*(COMMON)
		__bss_end = .;
		*(.sbss)
		*(.scommon)
	}
	__bss_len = ABSOLUTE(__bss_end) - ABSOLUTE(__bss_start);
	__bss_dwords = (__bss_len + 3) >> 2;

	. = ALIGN(128);
	
	/* Very large objects which don't need to be zeroed */

	.hugebss : {
		__hugebss_start = .;
		*(.hugebss)
		*(.hugebss.*)
		__hugebss_end = .;
	}

	_end = .;

	/* Stuff we don't need... */
	/DISCARD/ : {
		*(.eh_frame)
	}
}
