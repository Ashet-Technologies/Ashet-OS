/*
 * pow.S
 *
 * double pow(double base, double exponent)
 */

	.text
	.globl	pow
	.type	pow,@function
pow:
	fldl	12(%esp)
	fldl	4(%esp)
	fyl2x
	fld	%st(0)
	frndint
	fsubr	%st,%st(1)
	fxch	%st(1)
	f2xm1
	fld1
	faddp	%st,%st(1)
	fscale
	fstp	%st(1)
	ret

	.size	pow,.-pow
