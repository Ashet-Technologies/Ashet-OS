/*
 * arch/i386/libgcc/__muldi3.S
 *
 * 64*64 = 64 bit unsigned multiplication
 */

	.text
	.align 4
	.globl __muldi3
	.type __muldi3,@function
__muldi3:
#if __SIZEOF_POINTER__ == 4
	/* i386 */
	push  %esi
#ifndef REGPARM
	movl  8(%esp),%eax
	movl  %eax,%esi
	movl  16(%esp),%ecx
	mull  %ecx
	imull 12(%esp),%ecx
	imull 20(%esp),%esi
	addl  %ecx,%edx
	addl  %esi,%edx
#else
	movl  %eax,%esi
	push  %edx
	mull  %ecx
	imull 8(%esp),%esi
	addl  %esi,%edx
	pop   %esi
	imull %esi,%ecx
	addl  %ecx,%edx
#endif
	pop   %esi
	ret
#elif __SIZEOF_POINTER__ == 8
	/* x86_64 */
	push  %rsi
#ifndef REGPARM
/*
	movl  8(%esp),%eax
	movl %eax,%esi
	movl  16(%esp),%ecx
	mull  %ecx
	imull 12(%esp),%ecx
	imull 20(%esp),%esi
	addl  %ecx,%edx
	addl  %esi,%edx
*/
	movq  8(%rsp),%rax
	movq %rax,%rsi
	movq  16(%rsp),%rcx
	mulq  %rcx
	imulq 12(%rsp),%rcx
	imulq 20(%rsp),%rsi
	addq  %rcx,%rdx
	addq  %rsi,%rdx
#else
/*
	movl  %eax,%esi
	push  %edx
	mull  %ecx
	imull 8(%esp),%esi
	addl  %esi,%edx
	pop   %rsi
	imull %esi,%ecx
	addl  %ecx,%edx
*/
	movq  %rax,%rsi
	pushq  %rdx
	mulq  %rcx
	imulq 8(%rsp),%rsi
	addq  %rsi,%rdx
	popq  %rsi
	imulq %rsi,%rcx
	addq  %rcx,%rdx
#endif
	pop   %rsi
	ret
#else
#error "Unsupported architecture for __muldi3.S"
#endif
	.size __muldi3,.-__muldi3
