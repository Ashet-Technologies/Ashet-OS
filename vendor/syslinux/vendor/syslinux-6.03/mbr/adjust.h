/* -*- asm -*- -----------------------------------------------------------
 *
 *   Copyright 2009-2014 Intel Corporation; author: H. Peter Anvin
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
 * adjust.h
 *
 * Macros to adjust the drive number
 */

#ifndef ADJUST_H
#define ADJUST_H

#ifdef CTRL_80
	.macro ADJUST_DRIVE
	pusha
	movb	$0x02, %ah
	int	$0x16
	testb	$0x04, %al
	popa
	jz	1f
	movb	$0x80, %dl
1:
	.endm
#elif defined(FORCE_80)
	.macro ADJUST_DRIVE
	movb	$0x80, %dl
	.endm
#else
	.macro ADJUST_DRIVE
	.endm
#endif

#endif /* ADJUST_H */
