STACK_SIZE	= 8192
HEAP_SIZE	= 16384

		.section ".header","a"
		.balign	512
__header_start:
		.short	0x5a4d
		.short	_exe_edata_low
		.short	_exe_edata_blocks
		.short	0		/* Relocation count */
		.short	(__header_end - __header_start) >> 4
		.short	_exe_bss_paras
		.short	_exe_bss_paras
		.short	_exe_text_seg	/* SP */
		.short	__stack_end
		.short	0		/* Checksum */
		.short	_start
		.short	_exe_text_seg	/* CS */
		.short	__reloc
		.short	0		/* Overlay number */
/*
 * Don't put these fields in unless we actually have an NE or PE image;
 * some tools might get confused and assume __reloc = 64 automatically
 * means an NE/PE image or a Windows image of some sort.
 */
#if 0
		.short	0		/* Unknown/pad? */
		.short	0		/* Unknown/pad? */
		.short	0		/* Unknown/pad? */
		.short	0		/* Unknown/pad? */
		.short	0		/* Unknown/pad? */
		.short	0		/* Unknown/pad? */
		.short	0		/* Unknown/pad? */
		.short	0		/* Unknown/pad? */
		.short	0		/* Unknown/pad? */
		.short	0		/* Unknown/pad? */
		.short	0		/* Unknown/pad? */
		.short	0		/* Unknown/pad? */
		.short	0		/* Unknown/pad? */
		.short	0		/* Unknown/pad? */
		.short	0		/* Unknown/pad? */
		.short	0		/* Unknown/pad? */
		.long	0		/* Pointer to Windows PE header */
#endif
		.balign 4
__reloc:
		.balign	512
__header_end:

		.section ".heap","aw"
		.space	HEAP_SIZE

		.section ".stack","aw"
		.space	STACK_SIZE
