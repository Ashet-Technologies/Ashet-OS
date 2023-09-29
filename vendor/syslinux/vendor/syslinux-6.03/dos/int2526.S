/* ----------------------------------------------------------------------- *
 *
 *   Copyright 1998-2008 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * int 0x25 and 0x26 direct sector access
 *
 * Use assembly wrapper functions for these system calls, since unlike
 * int 0x21 calls they are "dirty" and can destroy unrelated registers.
 *
 * NOTE: these all assume the data buffer is in the data segment, i.e.
 * %ds == %es == dio.bufseg.
 *
 * Usage: int int25_read_sector(drive, dio)
 * Usage: int int26_write_sector(drive, dio)
 */

	.code16gcc
	.text

	.globl	int25_read_sector
	.type	int25_read_sector, @function
int25_read_sector:
	pushl	%ebp
	pushl	%edi
	pushl	%esi
	pushl	%ebx

	decw	%ax		/* AL = drive number (0 = A:) */
	movw	%dx, %bx	/* BX = dio structure */
	movw	6(%bx), %dx	/* DX = data buffer */
	movw	$-1, %cx
	int	$0x25
	jc	1f
	xorw	%ax, %ax	/* Error code: 0 = no error */
1:
	popfw
	movzwl	%ax, %eax
	popl	%ebx
	popl	%esi
	popl	%edi
	popl	%ebp
	retl
	.size	int25_read_sector, .-int25_read_sector

	.globl	int26_write_sector
	.type	int26_write_sector, @function
int26_write_sector:
	pushl	%ebp
	pushl	%edi
	pushl	%esi
	pushl	%ebx

	decw	%ax		/* AL = drive number (0 = A:) */
	movw	%dx, %bx	/* BX = dio structure */
	movw	6(%bx), %dx	/* DX = data buffer */
	movw	$-1, %cx
	int	$0x26
	jc	1f
	xorw	%ax, %ax	/* Error code: 0 = no error */
1:
	popfw
	movzwl	%ax, %eax
	popl	%ebx
	popl	%esi
	popl	%edi
	popl	%ebp
	retl
	.size	int26_write_sector, .-int26_write_sector
