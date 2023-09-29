/* -----------------------------------------------------------------------
 *
 *   Copyright 2003-2008 H. Peter Anvin - All Rights Reserved
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

/*
 * COM32 start up code - must be linked first in the binary
 */

/* Number of arguments in our version of the entry structure */
#define COM32_ARGS 9

		.section ".init","ax"
		.globl _start
		.type _start, @function
_start:
		/* This first instruction acts as COM32R magic number */
		movl $0x21cd4cfe,%eax

		/* Upwards string operations */
		cld

		/* Find our own location */
		call 1f
1:		popl %ebx
		addl $_GLOBAL_OFFSET_TABLE_ + (. - 1b), %ebx
	
		/* Process relocations (which overlay the .bss segment) */
		leal _edata@GOTOFF(%ebx),%esi
		leal _start@GOTOFF(%ebx),%edx
2:		lodsl
		andl %eax,%eax
		jz 3f
		addl %edx,(%eax,%edx)
		jmp 2b
3:
		/* Relocate the GOT (is this right?) */
		leal __got_start@GOTOFF(%ebx),%esi
		leal __got_end@GOTOFF(%ebx),%edi
4:
		addl %edx,(%esi)
		addl $4,%esi
		cmpl %edi,%esi
		jb 4b
	
		/* Zero the .bss segment */
		xorl %eax,%eax
		leal __bss_start@GOTOFF(%ebx),%edi
		leal _end+3@GOTOFF(%ebx),%ecx
		subl %edi,%ecx
		shrl $2,%ecx
		rep ; stosl

		/* Copy COM32 invocation parameters */
		leal 4(%esp),%esi		# Argument list
		leal __com32@GOTOFF(%ebx),%edi
		movl $(COM32_ARGS),%ecx
		movl %esp,-4(%edi)		# Save the initial stack ptr
		cmpl (%esi),%ecx
		jbe 5f
		movl (%esi),%ecx
5:		inc %ecx			# Copy the argument count, too
		rep ; movsl

		/* Parse the command line (assumes REGPARM) */
		movl __com32+4@GOTOFF(%ebx),%edx	# Command line
		pushl %edx				# Make space for argv
		movl %esp,%eax
		call __parse_argv
		pushl %eax				# Save argc

		/* Look for library initialization functions */
		leal __ctors_start@GOTOFF(%ebx),%esi
		leal __ctors_end@GOTOFF(%ebx),%edi
6:
		cmpl %edi,%esi
		jae 7f
		call *(%esi)
		addl $4,%esi
		jmp 6b
/*
 * Actually run main.  This assumes REGPARM is used!!!!
 */
7:
		popl %eax			# argc
		popl %edx			# argv
		call main
		call *__exit_handler@GOTOFF(%ebx)
		hlt
		.size _start, .-_start

		.bss
		.globl __entry_esp
__entry_esp:	.space 4
		.globl __com32
__com32:	.space 4*(COM32_ARGS+1)
