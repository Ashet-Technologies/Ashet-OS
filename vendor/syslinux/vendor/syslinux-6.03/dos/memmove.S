#
# memmove.S
#
# Simple 16-bit memmove() implementation
#

	.text
	.code16gcc
	.globl memmove
	.type memmove, @function
memmove:
	pushw %di
	pushw %si
	movw %ax,%di
	movw %dx,%si
	cmpw %si,%di
	ja 1f
	# The third argument is already in cx
	cld
	rep ; movsb
2:
	popw %si
	popw %di
	ret

1:	/* si <= di, need reverse copy */
	add %cx,%di
	add %cx,%si
	dec %di
	dec %si
	std
	rep ; movsb
	cld
	jmp 2b

	.size memmove,.-memmove
