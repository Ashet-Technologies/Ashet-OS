/* -----------------------------------------------------------------------
 *
 *   Copyright 2007-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * ----------------------------------------------------------------------- */

#include "adjust.h"

	.code16
	.text

	.globl	bootsec
stack		= 0x7c00

/* Partition table header here */
phdr		= stack		/* Above the stack, overwritten by bootsect */
/* Partition table sector here */
/* To handle > 32K we need to play segment tricks... */
psec		= _phdr + 512

/* Where we put DS:SI */
dssi_out	= _start + 0x1be

BIOS_kbdflags	= 0x417
BIOS_page	= 0x462

	/* gas/ld has issues with doing this as absolute addresses... */
	.section ".bootsec", "a", @nobits
	.globl	bootsec
bootsec:
	.space	512

	.text
	.globl	_start
_start:
	.byte	0x33, 0xc0	/* xorw	%ax, %ax */
	cli
	movw	%ax, %ds
	movw	%ax, %ss
	movw	$stack, %sp
	movw	%sp, %si
	pushw	%es		/* 4(%bp) es:di -> $PnP header */
	pushw	%di		/* 2(%bp) */
	movw	%ax, %es
	sti
	cld

	/* Copy down to 0:0x600 */
	movw	$_start, %di
	movw	$(512/2), %cx
	rep; movsw

	ljmpw	$0, $next
next:

	ADJUST_DRIVE
	pushw	%dx		/* 0(%bp) = %dl -> drive number */
	movw	%sp, %bp	/* %bp -> frame pointer: LEAVE UNCHANGED */

	/* prepare to read sector size */
	sub	$0x1c, %sp	/* -28(%bp) == %sp */
	pushw	$0x1e		/* -30(%bp) == %sp */
	movw	$0x200, -6(%bp)	/* -6(%bp) sector size */

	/* Check to see if we have EBIOS */
	pushw	%dx		/* drive number */
	movb	$0x41, %ah	/* %al == 0 already */
	movw	$0x55aa, %bx
	xorw	%cx, %cx
	xorb	%dh, %dh
	stc
	int	$0x13
	popw	%dx		/* restore drive */
	movb	$0x08, %ah	/* get CHS geometry */
	jc	1f
	cmpw	$0xaa55, %bx
	jne	1f
	shrw	%cx		/* Bit 0 = fixed disk subset */
	jnc	1f

	/* We have EBIOS; patch in the following code at
	   read_sector_cbios: movb $0x42, %ah ;  jmp read_common */
	movl	$0xeb42b4+((read_common-read_sector_cbios-4) << 24), \
		(read_sector_cbios)

	/*
	 * read sector size.
	 * Should not fail but if it does I assume that at least
	 * previous 512 value is not overridden
	 */
	movb	$0x48, %ah
	movw	%sp, %si

1:
	/* Get (C)HS geometry */
	int	$0x13

	/* here we computer CHS values or just do some dummy computation for EBIOS */
	andw	$0x3f, %cx	/* Sector count */
	pushw	%cx		/* -32(%bp) Save sectors on the stack */
	movzbw	%dh, %ax	/* dh = max head */
	incw	%ax		/* From 0-based max to count */
	mulw	%cx		/* Heads*sectors -> sectors per cylinder */

	/* Save sectors/cylinder on the stack */
	pushw	%dx		/* -34(%bp) High word */
	pushw	%ax		/* -36(%bp) Low word */

	/* Load partition table header */
	xorl	%eax,%eax
	cltd
	incw	%ax		/* %edx:%eax = 1 */
	call	read_sector_phdr

	/* Number of partition sectors */
	/* We assume the partition table is 32K or less */
	movw	(80+6)(%bp),%cx		/* NumberOfPartitionEntries */
	movw	(84+6)(%bp),%ax		/* SizeOfPartitionEntry */
	pushw	%ax
	pushw	%cx
	mulw	%cx
	divw	-6(%bp)	/* %dx == 0 here */
	xchgw	%ax,%cx
	incw	%cx

	/* Starting LBA of partition array */
	movl	(72+6)(%bp),%eax
	movl	(76+6)(%bp),%edx

	pushw	%bx
get_ptab:
	call	read_sector
	loopw	get_ptab

	/* Find the boot partition */
	xorw	%si,%si			/* Nothing found yet */
	popw	%di			/* Partition table in memory */
	popw	%cx			/* NumberOfPartitionEntries */
	popw	%ax			/* SizeOfPartitionEntry */

find_part:
	/* If the PartitionTypeGUID is all zero, it's an empty slot */
	movl	  (%di),%edx
	orl	 4(%di),%edx
	orl	 8(%di),%edx
	orl	12(%di),%edx
	jz	not_this
	testb	$0x04,48(%di)
	jz	not_this
	andw	%si,%si
	jnz	found_multiple
	movw	%di,%si
not_this:
	addw	%ax,%di
	loopw	find_part

	andw	%si,%si
	jnz	found_part

missing_os:
	call	error
	.ascii	"Missing OS\r\n"

found_multiple:
	call	error
	.ascii	"Multiple active partitions\r\n"

found_part:
	xchgw	%ax,%cx		/* Set up %cx for rep movsb further down */

	movw	$dssi_out,%di
	pushw	%di

	/* 80 00 00 00 ee 00 00 00
	   - bootable partition, type EFI (EE), no CHS information */
	xorl	%eax,%eax
	movb	$0x80,%al
	stosl
	movb	$0xed,%al
	stosl
	movl	32(%si),%eax
	movl	36(%si),%edx
	call	saturate_stosl		/* Partition start */

	movl	40(%si),%eax
	movl	44(%si),%edx
	subl	32(%si),%eax
	sbbl	36(%si),%edx
	call	inc64
	call	saturate_stosl		/* Partition length */

	movzwl	%cx,%eax		/* Length of GPT entry */
	stosl

	rep; movsb			/* GPT entry follows MBR entry */
	popw	%si

/*
 * boot: invoke the actual bootstrap. %ds:%si points to the
 * partition information in memory.  The top word on the stack
 * is phdr == 0x7c00 == the address of the boot sector.
 */
boot:
	movl	(32+20)(%si),%eax
	movl	(36+20)(%si),%edx
	call	read_sector_phdr
	cmpw	$0xaa55, (0x7c00+0x1fe)
	jne	missing_os	/* Not a valid boot sector */
	movw	%bp, %sp	/* driveno == bootsec-6 */
	popw	%dx		/* dl -> drive number */
	popw	%di		/* es:di -> $PnP vector */
	popw	%es
	movl	$0x54504721,%eax /* !GPT magic number */
	cli
	jmpw	*%sp		/* %sp == bootsec */

/*
 * Store the value in %eax to %di iff %edx == 0, otherwise store -1.
 * Returns the value that was actually written in %eax.
 */
saturate_stosl:
	andl	%edx,%edx
	jz 1f
	orl	$-1,%eax
1:	stosl
	ret

read_sector_phdr:
	movw	$phdr, %bx

	/* fall through and read sector */

/*
 * read_sector: read a single sector pointed to by %edx:%eax to
 * %es:%bx.  CF is set on error.  All registers saved.
 * %edx:%eax and %es:%bx are incremented to read next sector
 */
read_sector:
	pushal
	pushl	%edx	/* MSW of LBA */
	pushl	%eax	/* LSW of LBA */
	pushw	%es	/* Buffer segment */
	pushw	%bx	/* Buffer offset */
	pushw	$1	/* Sector count */
	pushw	$16	/* Size of packet */
	movw	%sp, %si

	/* This chunk is skipped if we have ebios */
	/* Do not clobber %es:%bx or %edx:%eax before this chunk! */
read_sector_cbios:
	divl	-36(%bp)	/* secpercyl */
	shlb	$6, %ah
	movb	%ah, %cl
	movb	%al, %ch
	xchgw	%dx, %ax
	divb	-32(%bp)	/* sectors */
	movb	%al, %dh
	orb	%ah, %cl
	incw	%cx	/* Sectors are 1-based */
	movw	$0x0201, %ax

read_common:
	movb	(%bp), %dl /* driveno */
	int	$0x13
	leaw	16(%si), %sp	/* Drop DAPA */
	popal
	jc	disk_error
	addb	-5(%bp), %bh		/* bx += sector size: point to the next buffer */

	/* fall through and increment sector number */

/*
 * Increment %edx:%eax
 */
inc64:
	addl	$1,%eax
	adcl	$0,%edx
	ret

disk_error:
	call	error
	.ascii	"Disk error\r\n"

/*
 * Print error messages.  This is invoked with "call", with the
 * error message at the return address.
 */
error:
	popw	%si
2:
	lodsb
	movb	$0x0e, %ah
	movb	(BIOS_page), %bh
	movb	$0x07, %bl
	int	$0x10		/* May destroy %bp */
	cmpb	$10, %al	/* Newline? */
	jne	2b

	int	$0x18		/* Boot failure */
die:
	hlt
	jmp	die
