	.code16

#ifndef REGPARM
# error "This file assumes -mregparm=3 -DREGPARM=3"
#endif

	.section ".text","ax"
	.globl _start
	.type _start,@function
_start:
	# Align the stack and make sure the high half is zero
	andl $0xfffc,%esp

	# DS, ES points to the PSP at this point
	pushw %es		# Save PSP pointer
	movw %cs,%ax
	movw %ax,%ds
	movw %ax,%es

	# Clear the .bss
	cld
	xorl %eax,%eax
	movw $__bss_start,%di
	movw $__bss_end+3,%cx
	subw %di,%cx
	shrw $2,%cx
	rep ; stosl

	# Copy the PSP into our own segment
	popw %fs		# FS -> PSP
	movw $_PSP,%di
	xorw %si,%si
	movw $0x40,%cx
	fs ; rep ; movsl

	# Verify that this is a supportable DOS version
	movw $0x3001,%ax
	int $0x21
	xchgb %ah,%al
	movw %ax,dos_version
	cmpw $0x0314,%ax	# DOS >= 3.20?
	jae 1f			# If so, okay
	movw $bad_dos,%dx	# Print error message
	movb $0x09,%ah
	int $0x21
	int $0x20		# Die

1:
	# Compute argc and argv (assumes REGPARM)
	pushl %eax		# Make space for argv
	movl %esp,%eax
	calll __parse_argv
	pushl %eax		# argc

	# Initialize malloc
	calll __init_memory_arena

	# Now call main
	popl %eax		# argc
	popl %edx		# argv
	calll main

	# Here %eax is the exit code, fall through into exit

	.size _start,.-_start

	.globl exit
	.type exit,@function
exit:
	# Exit code already in %eax
	movb $0x4c,%ah		# Terminate program
	int $0x21
1:	hlt
	jmp 1b
	.size exit,.-exit

	.section ".rodata","a"
bad_dos:
	.ascii "Unsupported DOS version\r\n$"
	.size bad_dos,.-bad_dos

	.section ".bss","aw"
	.balign 16
	.globl _PSP
_PSP:
	.space 256
	.size _PSP, .-_PSP

	/* Purely for sanity */
	.section ".null","a"
	.long 0,0,0,0
