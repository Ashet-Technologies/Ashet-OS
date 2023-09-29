	.globl	sem_down
	.type	sem_down, @function
sem_down:
	decl	(%eax)
	js	__sem_down_slow
	xorl	%eax, %eax
	ret
	.size	sem_down, .-sem_down

	.globl	sem_up
	.type	sem_up, @function
sem_up:
	incl	(%eax)
	jle	__sem_up_slow
	ret
	.size	sem_up, .-sem_up
