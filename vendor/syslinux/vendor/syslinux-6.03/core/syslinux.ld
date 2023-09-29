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
EXTERN(_start)
ENTRY(_start)

STACK32_LEN = 65536;

SECTIONS
{
	/* Prefix structure for the compression program */
	. = 0;
	HIDDEN(__module_start = .);
	.prefix : {
		*(.prefix)
	}

	/* "Early" sections (before the load) */
	. = 0x1000;

	.earlybss (NOLOAD) : {
		HIDDEN(__earlybss_start = .);
		*(.earlybss)
		HIDDEN(__earlybss_end = .);
	}
	HIDDEN(__earlybss_len = ABSOLUTE(__earlybss_end) - ABSOLUTE(__earlybss_start));
	HIDDEN(__earlybss_dwords = (__earlybss_len + 3) >> 2);

	. = ALIGN(4);
	.bss16 (NOLOAD) : {
		HIDDEN(__bss16_start = .);
		*(.bss16)
		HIDDEN(__bss16_end = .);
	}
	HIDDEN(__bss16_len = ABSOLUTE(__bss16_end) - ABSOLUTE(__bss16_start));
	HIDDEN(__bss16_dwords = (__bss16_len + 3) >> 2);

	. = ALIGN(4);
 	.config : AT (__config_lma) {
		HIDDEN(__config_start = .);
		*(.config)
		HIDDEN(__config_end = .);
	}
	HIDDEN(__config_len = ABSOLUTE(__config_end) - ABSOLUTE(__config_start));
	HIDDEN(__config_dwords = (__config_len + 3) >> 2);

	/* Generated and/or copied code */

	. = ALIGN(128);		/* Minimum separation from mutable data */
 	.replacestub : AT (__replacestub_lma) {
		HIDDEN(__replacestub_start = .);
		*(.replacestub)
		HIDDEN(__replacestub_end = .);
	}
	HIDDEN(__replacestub_len = ABSOLUTE(__replacestub_end) - ABSOLUTE(__replacestub_start));
	HIDDEN(__replacestub_dwords = (__replacestub_len + 3) >> 2);

	. = ALIGN(16);
	HIDDEN(__gentextnr_lma = .);
	.gentextnr : AT(__gentextnr_lma) {
		HIDDEN(__gentextnr_start = .);
		*(.gentextnr)
		HIDDEN(__gentextnr_end = .);
	}
	HIDDEN(__gentextnr_len = ABSOLUTE(__gentextnr_end) - ABSOLUTE(__gentextnr_start));
	HIDDEN(__gentextnr_dwords = (__gentextnr_len + 3) >> 2);

	. = STACK_BASE;
	.stack16 : AT(STACK_BASE) {
		HIDDEN(__stack16_start = .);
		. += STACK_LEN;
		HIDDEN(__stack16_end = .);
	}
	HIDDEN(__stack16_len = ABSOLUTE(__stack16_end) - ABSOLUTE(__stack16_start));
	HIDDEN(__stack16_dwords = (__stack16_len + 3) >> 2);

	/* Initialized sections */

	. = 0x7c00;
	.init : {
		FILL(0x90909090)
		HIDDEN(__init_start = .);
		*(.init)
		HIDDEN(__init_end = .);
	}
	HIDDEN(__init_len = ABSOLUTE(__init_end) - ABSOLUTE(__init_start));
	HIDDEN(__init_dwords = (__init_len + 3) >> 2);

	.text16 : {
		FILL(0x90909090)
		HIDDEN(__text16_start = .);
		*(.text16)
		HIDDEN(__text16_end = .);
	}
	HIDDEN(__text16_len = ABSOLUTE(__text16_end) - ABSOLUTE(__text16_start));
	HIDDEN(__text16_dwords = (__text16_len + 3) >> 2);

	/*
	 * .textnr is used for 32-bit code that is used on the code
	 * path to initialize the .text segment
	 */
	. = ALIGN(16);
	.textnr : {
		FILL(0x90909090)
		HIDDEN(__textnr_start = .);
		*(.textnr)
		HIDDEN(__textnr_end = .);
	}
	HIDDEN(__textnr_len = ABSOLUTE(__textnr_end) - ABSOLUTE(__textnr_start));
	HIDDEN(__textnr_dwords = (__textnr_len + 3) >> 2);

	. = ALIGN(16);
	HIDDEN(__bcopyxx_start = .);

	.bcopyxx.text : {
		FILL(0x90909090)
		HIDDEN(__bcopyxx_text_start = .);
		*(.bcopyxx.text)
		HIDDEN(__bcopyxx_text_end = .);
	}
	HIDDEN(__bcopyxx_text_len = ABSOLUTE(__bcopyxx_text_end) - ABSOLUTE(__bcopyxx_text_start));
	HIDDEN(__bcopyxx_text_dwords = (__bcopyxx_text_len + 3) >> 2);

	.bcopyxx.data : {
		HIDDEN(__bcopyxx_data_start = .);
		*(.bcopyxx.text)
		HIDDEN(__bcopyxx_data_end = .);
	}
	HIDDEN(__bcopyxx_data_len = ABSOLUTE(__bcopyxx_data_end) - ABSOLUTE(__bcopyxx_data_start));
	HIDDEN(__bcopyxx_data_dwords = (__bcopyxx_data_len + 3) >> 2);

	HIDDEN(__bcopyxx_end = .);
	HIDDEN(__bcopyxx_len = ABSOLUTE(__bcopyxx_end) - ABSOLUTE(__bcopyxx_start));
	HIDDEN(__bcopyxx_dwords = (__bcopyxx_len + 3) >> 2);

	. = ALIGN(4);
	.data16 : {
		HIDDEN(__data16_start = .);
		*(.data16)
		HIDDEN(__data16_end = .);
	}
	HIDDEN(__data16_len = ABSOLUTE(__data16_end) - ABSOLUTE(__data16_start));
	HIDDEN(__data16_dwords = (__data16_len + 3) >> 2);

	. = ALIGN(4);
	HIDDEN(__config_lma = .);
	. += SIZEOF(.config);

	. = ALIGN(4);
	HIDDEN(__replacestub_lma = .);
	. += SIZEOF(.replacestub);

	/* The 32-bit code loads above the non-progbits sections */

	. = ALIGN(16);
	HIDDEN(__pm_code_lma = .);

	HIDDEN(__high_clear_start = .);

	. = ALIGN(512);
	.adv (NOLOAD) : {
		HIDDEN(__adv_start = .);
		*(.adv)
		HIDDEN(__adv_end = .);
	}
	HIDDEN(__adv_len = ABSOLUTE(__adv_end) - ABSOLUTE(__adv_start));
	HIDDEN(__adv_dwords = (__adv_len + 3) >> 2);

	/* Late uninitialized sections */

	. = ALIGN(4);
	.uibss (NOLOAD) : {
		HIDDEN(__uibss_start = .);
		*(.uibss)
		HIDDEN(__uibss_end = .);
	}
	HIDDEN(__uibss_len = ABSOLUTE(__uibss_end) - ABSOLUTE(__uibss_start));
	HIDDEN(__uibss_dwords = (__uibss_len + 3) >> 2);

	HIDDEN(_end16 = .);
	HIDDEN(__assert_end16 = ASSERT(_end16 <= 0x10000, "64K overflow"));

	/*
	 * Special 16-bit segments
	 */

	. = ALIGN(65536);
	.real_mode (NOLOAD) : {
		*(.real_mode)
	}
	HIDDEN(real_mode_seg = core_real_mode >> 4);

	. = ALIGN(65536);
	.xfer_buf (NOLOAD) : {
		*(.xfer_buf)
	}
	HIDDEN(xfer_buf_seg = core_xfer_buf >> 4);

	/*
	 * Used to allocate lowmem buffers from 32-bit code
	 */
	.lowmem (NOLOAD) : {
		HIDDEN(__lowmem_start = .);
		*(.lowmem)
		HIDDEN(__lowmem_end = .);
	}
	HIDDEN(__lowmem_len = ABSOLUTE(__lowmem_end) - ABSOLUTE(__lowmem_start));
	HIDDEN(__lowmem_dwords = (__lowmem_len + 3) >> 2);

	HIDDEN(__high_clear_end = .);

	HIDDEN(__high_clear_len = ABSOLUTE(__high_clear_end) - ABSOLUTE(__high_clear_start));
	HIDDEN(__high_clear_dwords = (__high_clear_len + 3) >> 2);

	/* Start of the lowmem heap */
	. = ALIGN(16);
	HIDDEN(__lowmem_heap = .);

	/*
	 * 32-bit code.  This is a hack for the moment due to the
	 * real-mode segments also allocated.
	 */

	. = 0x100000;

	HIDDEN(__pm_code_start = .);

	HIDDEN(__text_vma = .);
	HIDDEN(__text_lma = __pm_code_lma);
	.text : AT(__text_lma) {
		FILL(0x90909090)
		HIDDEN(__text_start = .);
		*(.text)
		*(.text.*)
		HIDDEN(__text_end = .);
	}

	. = ALIGN(16);

	HIDDEN(__rodata_vma = .);
	HIDDEN(__rodata_lma = __rodata_vma + __text_lma - __text_vma);
	.rodata : AT(__rodata_lma) {
		HIDDEN(__rodata_start = .);
		*(.rodata)
		*(.rodata.*)
		HIDDEN(__rodata_end = .);
	}

	. = ALIGN(4);

	HIDDEN(__ctors_vma = .);
	HIDDEN(__ctors_lma = __ctors_vma + __text_lma - __text_vma);
	.ctors : AT(__ctors_lma) {
		HIDDEN(__ctors_start = .);
		KEEP (*(SORT(.preinit_array*)))
		KEEP (*(SORT(.init_array*)))
		KEEP (*(SORT(.ctors*)))
		HIDDEN(__ctors_end = .);
	}

	HIDDEN(__dtors_vma = .);
	HIDDEN(__dtors_lma = __dtors_vma + __text_lma - __text_vma);
	.dtors : AT(__dtors_lma) {
		HIDDEN(__dtors_start = .);
		KEEP (*(SORT(.fini_array*)))
		KEEP (*(SORT(.dtors*)))
		HIDDEN(__dtors_end = .);
	}

	. = ALIGN(4);

	HIDDEN(__dynsym_vma = .);
	HIDDEN(__dynsym_lma = __dynsym_vma + __text_lma - __text_vma);
	.dynsym : AT(__dynsym_lma) {
		HIDDEN(__dynsym_start = .);
		*(.dynsym)
		HIDDEN(__dynsym_end = .);
	}
	HIDDEN(__dynsym_len = __dynsym_end - __dynsym_start);

	. = ALIGN(4);

	HIDDEN(__dynstr_vma = .);
	HIDDEN(__dynstr_lma = __dynstr_vma + __text_lma - __text_vma);
	.dynstr : AT(__dynstr_lma) {
		HIDDEN(__dynstr_start = .);
		*(.dynstr)
		HIDDEN(__dynstr_end = .);
	}
	HIDDEN(__dynstr_len = __dynstr_end - __dynstr_start);

	. = ALIGN(4);

	HIDDEN(__gnu_hash_vma = .);
	HIDDEN(__gnu_hash_lma = __gnu_hash_vma + __text_lma - __text_vma);
	.gnu.hash : AT(__gnu_hash_lma) {
		HIDDEN(__gnu_hash_start = .);
		*(.gnu.hash)
		HIDDEN(__gnu_hash_end = .);
	}


	. = ALIGN(4);

	HIDDEN(__dynlink_vma = .);
	HIDDEN(__dynlink_lma = __dynlink_vma + __text_lma - __text_vma);
	.dynlink : AT(__dynlink_lma) {
		HIDDEN(__dynlink_start = .);
		*(.dynlink)
		HIDDEN(__dynlink_end = .);
	}

	. = ALIGN(4);

	HIDDEN(__got_vma = .);
	HIDDEN(__got_lma = __got_vma + __text_lma - __text_vma);
	.got : AT(__got_lma) {
		HIDDEN(__got_start = .);
		KEEP (*(.got.plt))
		KEEP (*(.got))
		HIDDEN(__got_end = .);
	}

	. = ALIGN(4);

	HIDDEN(__dynamic_vma = .);
	HIDDEN(__dynamic_lma = __dynamic_vma + __text_lma - __text_vma);
	.dynamic : AT(__dynamic_lma) {
		HIDDEN(__dynamic_start = .);
		*(.dynamic)
		HIDDEN(__dynamic_end = .);
	}

	. = ALIGN(16);

	HIDDEN(__data_vma = .);
	HIDDEN(__data_lma = __data_vma + __text_lma - __text_vma);
	.data : AT(__data_lma) {
		HIDDEN(__data_start = .);
		*(.data)
		*(.data.*)
		HIDDEN(__data_end = .);
	}

	HIDDEN(__pm_code_end = .);
	HIDDEN(__pm_code_len = ABSOLUTE(__pm_code_end) - ABSOLUTE(__pm_code_start));
	HIDDEN(__pm_code_dwords = (__pm_code_len + 3) >> 2);

	. = ALIGN(128);
	
	HIDDEN(__bss_vma = .);
	HIDDEN(__bss_lma = .);		/* Dummy */
	.bss (NOLOAD) : AT (__bss_lma) {
		HIDDEN(__bss_start = .);
		*(.bss)
		*(.bss.*)
		*(COMMON)
		HIDDEN(__bss_end = .);
	}
	HIDDEN(__bss_len = ABSOLUTE(__bss_end) - ABSOLUTE(__bss_start));
	HIDDEN(__bss_dwords = (__bss_len + 3) >> 2);

	/* Data saved away before bss initialization */
	. = ALIGN(128);

	HIDDEN(__savedata_vma = .);
	HIDDEN(__savedata_lma = .);		/* Dummy */
	.savedata (NOLOAD) : AT (__savedata_lma) {
		HIDDEN(__savedata_start = .);
		*(.savedata)
		*(.savedata.*)
		HIDDEN(__savedata_end = .);
	}
	HIDDEN(__savedata_len = ABSOLUTE(__savedata_end) - ABSOLUTE(__savedata_start));
	HIDDEN(__savedata_dwords = (__savedata_len + 3) >> 2);

	/* XXX: This stack should be unified with the COM32 stack */
	HIDDEN(__stack_vma = .);
	__stack_lma = .;	/* Dummy */
	.stack (NOLOAD) : AT(__stack_lma) {
		HIDDEN(__stack_start = .);
		*(.stack)
		HIDDEN(__stack_end = .);
	}
	HIDDEN(__stack_len = ABSOLUTE(__stack_end) - ABSOLUTE(__stack_start));
	HIDDEN(__stack_dwords = (__stack_len + 3) >> 2);

	HIDDEN(_end = .);

	/* Heap follows after our own PM code */
	. = ALIGN(65536);
	HIDDEN(free_high_memory = .);

	/* Stuff we don't need... */
	/DISCARD/ : {
		*(.eh_frame)
	}
}
