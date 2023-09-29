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

#define CR0_PG_FLAG	0x80000000
#define MSR_EFER	0xc0000080

	.globl kernel_jump
	.type kernel_jump,@function
	.code64
kernel_jump:
	cli

	/*
	 * Setup our segment selector (0x10) and return address (%rdi)
	 * on the stack in preparation for the far return below.
	 */
	mov	$0x1000000000, %rcx
	addq	%rcx, %rdi
	pushq	%rdi

	.code32
pm_code:

	/* Disable IA-32e mode by clearing IA32_EFER.LME */
	xorl	%eax, %eax
	xorl	%edx, %edx
	movl	$MSR_EFER, %ecx
	wrmsr

	/* Turn off paging to disable long mode */
	movl	%cr0, %eax
	andl	$~CR0_PG_FLAG, %eax
	movl	%eax, %cr0

	/* Far return */
	lret

	.code64
	.align 4
	.globl efi_handover_32
	.type  efi_handover_32,@function
efi_handover_32:
	movl	$38, errno(%rip)	/* ENOSYS */
	ret

	.globl efi_handover_64
	.globl efi_handover
	.type  efi_handover_64,@function
	.type  efi_handover,@function
efi_handover_64:
efi_handover:
	add	$512, %rcx
	cli
	jmp	*%rcx
