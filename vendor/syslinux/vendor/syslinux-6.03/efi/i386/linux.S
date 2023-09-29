/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2013 Intel Corporation; author: Matt Fleming
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

	.globl kernel_jump
	.type  kernel_jump,@function
	.text
kernel_jump:
	cli
	movl	0x8(%esp), %esi
	movl	0x4(%esp), %ecx
	jmp	*%ecx

	/*
	 * The default handover function should only be invoked for
	 * bzImage boot protocol versions < 2.12.
	 */
	.globl efi_handover
	.type  efi_handover,@function
efi_handover:
	cli
	popl	%ecx		/* discard return address */
	movl	0xc(%esp), %ecx
	jmp	*%ecx

	.globl efi_handover_32
	.type  efi_handover_32,@function
efi_handover_32:
	cli
	popl	%ecx		/* discard return address */
	movl	0xc(%esp), %ecx
	call	*%ecx

	.globl efi_handover_64
	.type  efi_handover_64,@function
efi_handover_64:
	call	1f
1:
	popl	%eax
	subl	$1b, %eax
	movl	$38, errno(%eax)	/* ENOSYS */
	ret
