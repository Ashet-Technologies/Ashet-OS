/*
 * Wrap ldlinux.sys and ldlinux.c32; this needs special handling for DOS.
 */

	.section ".payload","aw"
	.balign	16
	.globl	syslinux_ldlinux, syslinux_ldlinux_size
syslinux_ldlinux:
	.incbin "../core/ldlinux.sys"
	.space ((syslinux_ldlinux - .) & 511)
syslinux_ldlinux_size	= . - syslinux_ldlinux
	.size	syslinux_ldlinux, .-syslinux_ldlinux
	.globl	syslinux_ldlinuxc32, syslinux_ldlinuxc32_size
syslinux_ldlinuxc32:
	.incbin "../com32/elflink/ldlinux/ldlinux.c32"
	.space ((syslinux_ldlinuxc32 - .) & 511)
syslinux_ldlinuxc32_size = . - syslinux_ldlinuxc32
	.size	syslinux_ldlinuxc32, .-syslinux_ldlinuxc32
	.globl syslinux_size
syslinux_size	= . - syslinux_ldlinux

	.section ".rodata","a"
	.balign	4
	.globl	syslinux_ldlinux_len
syslinux_ldlinux_len:
	.long	syslinux_ldlinux_size
	.size	syslinux_ldlinux_len, .-syslinux_ldlinux_len
	.globl	syslinux_ldlinuxc32_len
syslinux_ldlinuxc32_len:
	.long	syslinux_ldlinuxc32_size
	.size	syslinux_ldlinuxc32_len, .-syslinux_ldlinuxc32_len
