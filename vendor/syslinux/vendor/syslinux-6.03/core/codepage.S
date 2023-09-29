	.section ".rodata","a"
	.globl	codepage
codepage:
	.incbin "codepage.cp"
	.size	codepage, .-codepage
