/* -----------------------------------------------------------------------
 *
 *   Copyright 2007-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
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
driveno		= (stack-6)
sectors		= (stack-8)
secpercyl	= (stack-12)

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
	pushw	%es		/* es:di -> $PnP header */
	pushw	%di
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
	pushw	%dx		/* dl -> drive number */

	/* Check to see if we have EBIOS */
	pushw	%dx		/* drive number */
	movb	$0x41, %ah	/* %al == 0 already */
	movw	$0x55aa, %bx
	xorw	%cx, %cx
	xorb	%dh, %dh
	stc
	int	$0x13
	jc	1f
	cmpw	$0xaa55, %bx
	jne	1f
	shrw	%cx		/* Bit 0 = fixed disk subset */
	jnc	1f

	/* We have EBIOS; patch in the following code at
	   read_sector_cbios: movb $0x42, %ah ;  jmp read_common */
	movl	$0xeb42b4+((read_common-read_sector_cbios-4) << 24), \
		(read_sector_cbios)

1:
	popw	%dx

	/* Get (C)HS geometry */
	movb	$0x08, %ah
	int	$0x13
	andw	$0x3f, %cx	/* Sector count */
	pushw	%cx		/* Save sectors on the stack */
	movzbw	%dh, %ax	/* dh = max head */
	incw	%ax		/* From 0-based max to count */
	mulw	%cx		/* Heads*sectors -> sectors per cylinder */

	/* Save sectors/cylinder on the stack */
	pushw	%dx		/* High word */
	pushw	%ax		/* Low word */

	xorl	%eax, %eax	/* Base */
	cdq			/* Root (%edx <- 0) */
	call	scan_partition_table

	/* If we get here, we have no OS */
missing_os:
	call	error
	.ascii	"Missing operating system.\r\n"

/*
 * read_sector: read a single sector pointed to by %eax to 0x7c00.
 * CF is set on error.  All registers saved.
 */
read_sector:
	pushal
	xorl	%edx, %edx
	movw	$bootsec, %bx
	pushl	%edx	/* MSW of LBA */
	pushl	%eax	/* LSW of LBA */
	pushw	%es	/* Buffer segment */
	pushw	%bx	/* Buffer offset */
	pushw	$1	/* Sector count */
	pushw	$16	/* Size of packet */
	movw	%sp, %si

	/* This chunk is skipped if we have ebios */
	/* Do not clobber %eax before this chunk! */
	/* This also relies on %bx and %edx as set up above. */
read_sector_cbios:
	divl	(secpercyl)
	shlb	$6, %ah
	movb	%ah, %cl
	movb	%al, %ch
	xchgw	%dx, %ax
	divb	(sectors)
	movb	%al, %dh
	orb	%ah, %cl
	incw	%cx	/* Sectors are 1-based */
	movw	$0x0201, %ax

read_common:
	movb	(driveno), %dl
	int	$0x13
	leaw	16(%si), %sp	/* Drop DAPA */
	popal
	ret

/*
 * read_partition_table:
 *	Read a partition table (pointed to by %eax), and copy
 *	the partition table into the ptab buffer.
 *
 *	Clobbers %si, %di, and %cx, other registers preserved.
 *	%cx = 0 on exit.
 *
 *	On error, CF is set and ptab is overwritten with junk.
 */
ptab	= _start+446

read_partition_table:
	call	read_sector
	movw	$bootsec+446, %si
	movw	$ptab, %di
	movw	$(16*4/2), %cx
	rep ; movsw
	ret

/*
 * scan_partition_table:
 *	Scan a partition table currently loaded in the partition table
 *	area.  Preserve all registers.
 *
 *      On entry:
 *	  %eax - base (location of this partition table)
 *	  %edx - root (offset from MBR, or 0 for MBR)
 *
 *      These get pushed into stack slots:
 *        28(%bp) - %eax - base
 *	  20(%bp) - %edx - root
 */

scan_partition_table:
	pushal
	movw	%sp, %bp

	/* Search for active partitions */
	movw	$ptab, %bx
	movw	$4, %cx
	xorw	%ax, %ax
	push	%bx
	push	%cx
5:
	testb	$0x80, (%bx)
	jz	6f
	incw	%ax
	movw	%bx, %si
6:
	addw	$16, %bx
	loopw	5b

	decw	%ax		/* Number of active partitions found */
	jz	boot
	jns	too_many_active

	/* No active partitions found, look for extended partitions */
	popw	%cx		/* %cx <- 4    */
	popw	%bx		/* %bx <- ptab */
7:
	movb	4(%bx), %al
	cmpb	$0x0f, %al	/* 0x0f = Win9x extended */
	je	8f
	andb	$~0x80, %al	/* 0x85 = Linux extended */
	cmpb	$0x05, %al	/* 0x05 = MS-DOS extended */
	jne	9f

	/* It is an extended partition.  Read the extended partition and
	   try to scan it.  If the scan returns, re-load the current
	   partition table and resume scan. */
8:
	movl	8(%bx), %eax		/* Partition table offset */
	movl	20(%bp), %edx		/* "Root" */
	addl	%edx, %eax		/* Compute location of new ptab */
	andl	%edx, %edx		/* Is this the MBR? */
	jnz	10f
	movl	%eax, %edx		/* Offset -> root if this was MBR */
10:
	call	read_partition_table
	jc	11f
	call	scan_partition_table
11:
	/* This returned, so we need to reload the current partition table */
	movl	28(%bp), %eax		/* "Base" */
	call	read_partition_table

	/* fall through */
9:
	/* Not an extended partition */
	addw	$16, %bx
	loopw	7b

	/* Nothing found, return */
	popal
	ret

too_many_active:
	call	error
	.ascii	"Multiple active partitions.\r\n"

/*
 * boot: invoke the actual bootstrap. (%si) points to the partition
 *	 table entry, and 28(%bp) has the partition table base.
 */
boot:
	movl	8(%si), %eax
	addl	28(%bp), %eax
	movl	%eax, 8(%si)	/* Adjust in-memory partition table entry */
	call	read_sector
	jc	disk_error

	/* Check if the read sector is a XFS superblock */
	cmpl	$0x42534658, (bootsec) /* "XFSB" */
	jne	no_xfs

	/* We put the Syslinux boot sector at offset 0x800 (4 sectors), so we
	 * need to adjust %eax (%eax + 4) to read the right sector into 0x7C00.
	 */
	addl	$0x800 >> 0x09, %eax /* plus 4 sectors */
	call	read_sector
	jc	disk_error

no_xfs:
	cmpw	$0xaa55, (bootsec+510)
	jne	missing_os		/* Not a valid boot sector */
	movw	$driveno, %sp	/* driveno == bootsec-6 */
	popw	%dx		/* dl -> drive number */
	popw	%di		/* es:di -> $PnP vector */
	popw	%es
	cli
	jmpw	*%sp		/* %sp == bootsec */

disk_error:
	call	error
	.ascii	"Operating system load error.\r\n"

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
