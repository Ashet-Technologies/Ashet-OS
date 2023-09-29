	.globl	__switch_to
	.type	__switch_to, @function
__switch_to:
	movl	__current, %edx
	pushl	%ebx
	pushl	%ebp
	pushl	%esi
	pushl	%edi
	pushl	RealModeSSSP
	pushl	errno			/* Hack! */
	movl	%esp, (%edx)

	movl	%eax, __current
	movl	(%eax), %esp
	popl	errno
	popl	RealModeSSSP
	popl	%edi
	popl	%esi
	popl	%ebp
	popl	%ebx
	ret
	.size	__switch_to, .-__switch_to

	.globl	__start_thread
	.type	__start_thread, @function
__start_thread:
	movl	%edi, %eax		/* Thread function argument */

	pushl	$0			/* For gdb's benefit */
	movl	%esp, %ebp		/* For gdb's benefit */

	pushl	%ebx			/* Set up the flags/interrupt state */
	popfl

	call	*%esi			/* Run the desired function */
	jmp	__exit_thread		/* If we get here, kill the thread */
	.size	__start_thread, .-__start_thread
