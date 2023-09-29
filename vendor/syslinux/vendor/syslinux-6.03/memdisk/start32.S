/* -----------------------------------------------------------------------
 *
 *   Copyright 2003-2009 H. Peter Anvin - All Rights Reserved
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
 * Simple stub to get us to the right point in the 32-bit code;
 * this module must be linked first
 */

	.section ".init", "ax"
	.globl _start
_start:
	/* Zero the bss */
	cld
	movl	$__bss_start, %edi
	movl	$__bss_end, %ecx
	subl	%edi, %ecx
	xorl	%eax, %eax
	shrl	$2, %ecx
	rep ; stosl

	/* Set up the protected-mode IDT and the interrupt jump buffers */
	movl	$idt, %edi
	movl	$ijb, %eax
	movl	$0xee000000, %ebx	/* Interrupt gate */
	movw	%cs, %bx		/* Target segment */

	/* Make the IDT */
	movl	$256, %ecx
1:
	stosl
	stosl
	movl	%ebx, -6(%edi)
	addl	$8, %eax
	loop	1b

	/*
	 * Each entry in the interrupt jump buffer contains the following
	 * instructions:
	 *
	 * 60		pushal
	 * b0xx		movb $xx, %al		# interrupt number
	 * e9xxxxxxxx	jmp handle_interrupt
	 */
	movl	$0xe900b060, %eax
	movl	$256, %ecx
1:
	movl	%eax, (%edi)
	addl	$(1 << 16), %eax
	movl	$handle_interrupt-8, %edx
	subl	%edi, %edx
	movl	%edx, 4(%edi)
	addl	$8, %edi
	loop	1b

#if __SIZEOF_POINTER__ == 4
	lidtl	idt_ptr
#elif __SIZEOF_POINTER__ == 8
	lidt	idt_ptr
#else
#error "unsupported architecture"
#endif
	
	/* Save arguments, switch stacks */
	movl	%esp, %eax		/* Pointer to arguments */
	movl	$__stack_end, %esp
	
	call	setup
	jmp	*(rm_args)		/* First argument is return */

	.section ".text","ax"
	.globl	intcall
	.type	intcall, @function
intcall:
	jmp	*(rm_args+1*4)		/* Intcall is argument 1 */
	.size	intcall, .-intcall

	.type	handle_interrupt, @function
handle_interrupt:
	jmp	*(rm_args+4*4)		/* Interrupt pointer is argument 4 */
	.size	handle_interrupt, .-handle_interrupt

	.section ".rodata","a"
idt_ptr:
	.word	8*256-1
	.long	idt
	.word	0

	.section ".bss.large","aw"
	.balign 2048
idt:
	.space	8*256
ijb:
	.space	8*256

__stack:
	.space	65536
__stack_end:
