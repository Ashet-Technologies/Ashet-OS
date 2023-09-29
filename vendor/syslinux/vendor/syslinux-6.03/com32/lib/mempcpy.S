/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2008 H. Peter Anvin - All Rights Reserved
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
 * mempcpy.S
 *
 * Reasonably efficient mempcpy, using aligned transfers at least
 * for the destination operand.
 */

	.text
	.globl	mempcpy
	.type	mempcpy, @function
mempcpy:
	movl	0xc(%esp),%ecx
	movl	0x8(%esp),%edx
	movl	0x4(%esp),%eax

	jecxz	1f

	pushl	%esi
	pushl	%edi

	movl	%eax,%edi
	movl	%edx,%esi

	/* Initial alignment */
	movl	%edi,%edx
	shrl	$1,%edx
	jnc	11f
	movsb
	decl	%ecx
11:
	movb	%cl,%al
	cmpl	$2,%ecx
	jb	13f

	shrl	$1,%edx
	jnc	12f
	movsw
	subl	$2,%ecx
12:
	/* Bulk transfer */
	movb	%cl,%al
	shrl	$2,%ecx
	rep; movsl

	/* Final alignment */
	testb	$2,%al
	jz	14f
	movsw
13:
14:
	testb	$1,%al
	jz	15f
	movsb
15:

	movl	%edi,%eax	/* Return value */
	popl	%edi
	popl	%esi
1:
	ret

	.size	mempcpy, .-mempcpy
