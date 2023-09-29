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
	__module_start = .;
	.prefix : {
		*(.prefix)
	}

	/* "Early" sections (before the load) */
	. = 0x1000;

	.earlybss (NOLOAD) : {
		__earlybss_start = .;
		*(.earlybss)
		__earlybss_end = .;
	}
	__earlybss_len = ABSOLUTE(__earlybss_end) - ABSOLUTE(__earlybss_start);
	__earlybss_dwords = (__earlybss_len + 3) >> 2;

	. = ALIGN(4);
	.bss16 (NOLOAD) : {
		__bss16_start = .;
		*(.bss16)
		__bss16_end = .;
	}
	__bss16_len = ABSOLUTE(__bss16_end) - ABSOLUTE(__bss16_start);
	__bss16_dwords = (__bss16_len + 3) >> 2;

	. = ALIGN(4);
 	.config : AT (__config_lma) {
		__config_start = .;
		*(.config)
		__config_end = .;
	}
	__config_len = ABSOLUTE(__config_end) - ABSOLUTE(__config_start);
	__config_dwords = (__config_len + 3) >> 2;

	/* Generated and/or copied code */

	. = ALIGN(128);		/* Minimum separation from mutable data */
 	.replacestub : AT (__replacestub_lma) {
		__replacestub_start = .;
		*(.replacestub)
		__replacestub_end = .;
	}
	__replacestub_len = ABSOLUTE(__replacestub_end) - ABSOLUTE(__replacestub_start);
	__replacestub_dwords = (__replacestub_len + 3) >> 2;

	. = ALIGN(16);
	__gentextnr_lma = .;
	.gentextnr : AT(__gentextnr_lma) {
		__gentextnr_start = .;
		*(.gentextnr)
		__gentextnr_end = .;
	}
	__gentextnr_len = ABSOLUTE(__gentextnr_end) - ABSOLUTE(__gentextnr_start);
	__gentextnr_dwords = (__gentextnr_len + 3) >> 2;

	. = STACK_BASE;
	.stack16 : AT(STACK_BASE) {
		__stack16_start = .;
		. += STACK_LEN;
		__stack16_end = .;
	}
	__stack16_len = ABSOLUTE(__stack16_end) - ABSOLUTE(__stack16_start);
	__stack16_dwords = (__stack16_len + 3) >> 2;

	/* Initialized sections */

	. = 0x7c00;
	.init : {
		FILL(0x90909090)
		__init_start = .;
		*(.init)
		__init_end = .;
	}
	__init_len = ABSOLUTE(__init_end) - ABSOLUTE(__init_start);
	__init_dwords = (__init_len + 3) >> 2;

	.text16 : {
		FILL(0x90909090)
		__text16_start = .;
		*(.text16)
		__text16_end = .;
	}
	__text16_len = ABSOLUTE(__text16_end) - ABSOLUTE(__text16_start);
	__text16_dwords = (__text16_len + 3) >> 2;

	/*
	 * .textnr is used for 32-bit code that is used on the code
	 * path to initialize the .text segment
	 */
	. = ALIGN(16);
	.textnr : {
		FILL(0x90909090)
		__textnr_start = .;
		*(.textnr)
		__textnr_end = .;
	}
	__textnr_len = ABSOLUTE(__textnr_end) - ABSOLUTE(__textnr_start);
	__textnr_dwords = (__textnr_len + 3) >> 2;

	. = ALIGN(16);
	__bcopyxx_start = .;

	.bcopyxx.text : {
		FILL(0x90909090)
		__bcopyxx_text_start = .;
		*(.bcopyxx.text)
		__bcopyxx_text_end = .;
	}
	__bcopyxx_text_len = ABSOLUTE(__bcopyxx_text_end) - ABSOLUTE(__bcopyxx_text_start);
	__bcopyxx_text_dwords = (__bcopyxx_text_len + 3) >> 2;

	.bcopyxx.data : {
		__bcopyxx_data_start = .;
		*(.bcopyxx.text)
		__bcopyxx_data_end = .;
	}
	__bcopyxx_data_len = ABSOLUTE(__bcopyxx_data_end) - ABSOLUTE(__bcopyxx_data_start);
	__bcopyxx_data_dwords = (__bcopyxx_data_len + 3) >> 2;

	__bcopyxx_end = .;
	__bcopyxx_len = ABSOLUTE(__bcopyxx_end) - ABSOLUTE(__bcopyxx_start);
	__bcopyxx_dwords = (__bcopyxx_len + 3) >> 2;

	. = ALIGN(4);
	.data16 : {
	      __data16_start = .;
	      *(.data16)
	      __data16_end = .;
	}
	__data16_len = ABSOLUTE(__data16_end) - ABSOLUTE(__data16_start);
	__data16_dwords = (__data16_len + 3) >> 2;

	. = ALIGN(4);
	__config_lma = .;
	. += SIZEOF(.config);

	. = ALIGN(4);
	__replacestub_lma = .;
	. += SIZEOF(.replacestub);

	/* The 32-bit code loads above the non-progbits sections */

	. = ALIGN(16);
	__pm_code_lma = .;

	__high_clear_start = .;

	. = ALIGN(512);
	.adv (NOLOAD) : {
		__adv_start = .;
		*(.adv)
		__adv_end = .;
	}
	__adv_len = ABSOLUTE(__adv_end) - ABSOLUTE(__adv_start);
	__adv_dwords = (__adv_len + 3) >> 2;

	/* Late uninitialized sections */

	. = ALIGN(4);
	.uibss (NOLOAD) : {
		__uibss_start = .;
		*(.uibss)
		__uibss_end = .;
	}
	__uibss_len = ABSOLUTE(__uibss_end) - ABSOLUTE(__uibss_start);
	__uibss_dwords = (__uibss_len + 3) >> 2;

	_end16 = .;
	__assert_end16 = ASSERT(_end16 <= 0x10000, "64K overflow");

	/*
	 * Special 16-bit segments
	 */

	. = ALIGN(65536);
	.real_mode (NOLOAD) : {
		*(.real_mode)
	}
	real_mode_seg = core_real_mode >> 4;

	. = ALIGN(65536);
	.xfer_buf (NOLOAD) : {
		*(.xfer_buf)
	}
	xfer_buf_seg = core_xfer_buf >> 4;

	/*
	 * The auxilliary data segment is used by the 16-bit code
	 * for items that don't need to live in the bottom 64K.
	 */

	. = ALIGN(16);
	.auxseg (NOLOAD) : {
		__auxseg_start = .;
		*(.auxseg)
		__auxseg_end = .;
	}
	__auxseg_len = ABSOLUTE(__auxseg_end) - ABSOLUTE(__auxseg_start);
	__auxseg_dwords = (__auxseg_len + 3) >> 2;
	aux_seg = __auxseg_start >> 4;

	/*
	 * Used to allocate lowmem buffers from 32-bit code
	 */
	.lowmem (NOLOAD) : {
		__lowmem_start = .;
		*(.lowmem)
		__lowmem_end = .;
	}
	__lowmem_len = ABSOLUTE(__lowmem_end) - ABSOLUTE(__lowmem_start);
	__lowmem_dwords = (__lowmem_len + 3) >> 2;

	__high_clear_end = .;

	__high_clear_len = ABSOLUTE(__high_clear_end) - ABSOLUTE(__high_clear_start);
	__high_clear_dwords = (__high_clear_len + 3) >> 2;

	/* Start of the lowmem heap */
	. = ALIGN(16);
	__lowmem_heap = .;

	/*
	 * 32-bit code.  This is a hack for the moment due to the
	 * real-mode segments also allocated.
	 */

	. = 0x100000;

	__pm_code_start = .;

	__text_vma = .;
	__text_lma = __pm_code_lma;
	.text : AT(__text_lma) {
		FILL(0x90909090)
		__text_start = .;
		*(.text)
		*(.text.*)
		__text_end = .;
	}

	. = ALIGN(16);

	__rodata_vma = .;
	__rodata_lma = __rodata_vma + __text_lma - __text_vma;
	.rodata : AT(__rodata_lma) {
		__rodata_start = .;
		*(.rodata)
		*(.rodata.*)
		__rodata_end = .;
	}

	. = ALIGN(4);

	__ctors_vma = .;
	__ctors_lma = __ctors_vma + __text_lma - __text_vma;
	.ctors : AT(__ctors_lma) {
		__ctors_start = .;
		KEEP (*(SORT(.ctors.*)))
		KEEP (*(.ctors))
		__ctors_end = .;
	}

	__dtors_vma = .;
	__dtors_lma = __dtors_vma + __text_lma - __text_vma;
	.dtors : AT(__dtors_lma) {
		__dtors_start = .;
		KEEP (*(SORT(.dtors.*)))
		KEEP (*(.dtors))
		__dtors_end = .;
	}

	. = ALIGN(4);

	__dynsym_vma = .;
	__dynsym_lma = __dynsym_vma + __text_lma - __text_vma;
	.dynsym : AT(__dynsym_lma) {
		__dynsym_start = .;
		*(.dynsym)
		__dynsym_end = .;
	}
	__dynsym_len = __dynsym_end - __dynsym_start;

	. = ALIGN(4);

	__dynstr_vma = .;
	__dynstr_lma = __dynstr_vma + __text_lma - __text_vma;
	.dynstr : AT(__dynstr_lma) {
		__dynstr_start = .;
		*(.dynstr)
		__dynstr_end = .;
	}
	__dynstr_len = __dynstr_end - __dynstr_start;

	. = ALIGN(4);

	__gnu_hash_vma = .;
	__gnu_hash_lma = __gnu_hash_vma + __text_lma - __text_vma;
	.gnu.hash : AT(__gnu_hash_lma) {
		__gnu_hash_start = .;
		*(.gnu.hash)
		__gnu_hash_end = .;
	}


	. = ALIGN(4);

	__dynlink_vma = .;
	__dynlink_lma = __dynlink_vma + __text_lma - __text_vma;
	.dynlink : AT(__dynlink_lma) {
		__dynlink_start = .;
		*(.dynlink)
		__dynlink_end = .;
	}

	. = ALIGN(4);

	__got_vma = .;
	__got_lma = __got_vma + __text_lma - __text_vma;
	.got : AT(__got_lma) {
		__got_start = .;
		KEEP (*(.got.plt))
		KEEP (*(.got))
		__got_end = .;
	}

	. = ALIGN(4);

	__dynamic_vma = .;
	__dynamic_lma = __dynamic_vma + __text_lma - __text_vma;
	.dynamic : AT(__dynamic_lma) {
		__dynamic_start = .;
		*(.dynamic)
		__dynamic_end = .;
	}

	. = ALIGN(16);

	__data_vma = .;
	__data_lma = __data_vma + __text_lma - __text_vma;
	.data : AT(__data_lma) {
		__data_start = .;
		*(.data)
		*(.data.*)
		__data_end = .;
	}

	__pm_code_end = .;
	__pm_code_len = ABSOLUTE(__pm_code_end) - ABSOLUTE(__pm_code_start);
	__pm_code_dwords = (__pm_code_len + 3) >> 2;

	. = ALIGN(128);
	
	__bss_vma = .;
	__bss_lma = .;		/* Dummy */
	.bss (NOLOAD) : AT (__bss_lma) {
		__bss_start = .;
		*(.bss)
		*(.bss.*)
		*(COMMON)
		__bss_end = .;
	}
	__bss_len = ABSOLUTE(__bss_end) - ABSOLUTE(__bss_start);
	__bss_dwords = (__bss_len + 3) >> 2;

	/* Very large objects which don't need to be zeroed */

	__hugebss_vma = .;
	__hugebss_lma = .;		/* Dummy */
	.hugebss (NOLOAD) : AT (__hugebss_lma) {
		__hugebss_start = .;
		*(.hugebss)
		*(.hugebss.*)
		__hugebss_end = .;
	}
	__hugebss_len = ABSOLUTE(__hugebss_end) - ABSOLUTE(__hugebss_start);
	__hugebss_dwords = (__hugebss_len + 3) >> 2;


	/* XXX: This stack should be unified with the COM32 stack */
	__stack_vma = .;
	__stack_lma = .;	/* Dummy */
	.stack (NOLOAD) : AT(__stack_lma) {
		__stack_start = .;
		*(.stack)
		__stack_end = .;
	}
	__stack_len = ABSOLUTE(__stack_end) - ABSOLUTE(__stack_start);
	__stack_dwords = (__stack_len + 3) >> 2;

	_end = .;

	/* COM32R and kernels are loaded after our own PM code */
	. = ALIGN(65536);
	free_high_memory = .;

	/* Stuff we don't need... */
	/DISCARD/ : {
		*(.eh_frame)
	}
}
