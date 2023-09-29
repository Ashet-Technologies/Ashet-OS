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
 * memset.S
 *
 * Reasonably efficient memset, using aligned transfers at least
 * for the destination operand.
 */

	.globl	memset
	.type	memset,@function
	.text
memset:
	jecxz	6f

	pushl	%edi
	pushl	%ebx
	pushl	%eax		/* Return value */

	movl	%eax,%edi
	movb	%dl,%dh
	movzwl	%dx,%eax
	shll	$16,%edx
	orl	%edx,%eax

	/* Initial alignment */
	movl	%edi,%edx
	shrl	$1,%edx
	jnc	1f
	stosb
	decl	%ecx
1:
	movb	%cl,%bl
	cmpl	$2,%ecx
	jb	3f
	shrl	$1,%edx
	jnc	2f
	stosw
	subl	$2,%ecx
2:
	/* Bulk transfer */
	movb	%cl,%bl
	shrl	$2,%ecx
	rep; stosl

	testb	$2,%bl
	jz	4f
	stosw
3:
4:
	testb	$1,%bl
	jz	5f
	stosb
5:
	popl	%eax		/* Return value */
	popl	%ebx
	popl	%edi
6:
	ret

	.size	memset, .-memset
