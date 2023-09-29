/* -----------------------------------------------------------------------
 *
 *   Copyright 2010-2011 Gene Cumm
 *
 *   Portions from mbr.S:
 *   Copyright 2007-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
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
 * handoff.S: MBR/VBR-like codeblock to display handoff data
 *
 * Displays the values of DL, DS, SI, the contents of [DS:SI] (16 bytes),
 * the values of ES, DI, the contents of [ES:DI] (4 bytes), scans memory for
 * $PnP then reports a boot failure.
 *
 * This should (hopefully) be only 8086 code
 */

/*
 * Install instructions (assuming your target is /dev/dev; file or block device):
 *
 * MBR:
 * dd conv=notrunc bs=440 count=1 if=handoff.bin of=/dev/dev
 *
 * VBR/PBR (should work for FAT12/16/32, ext[234]fs, btrfs):
 * echo -en "\0353\0130\0220" |dd conv=notrunc bs=1 count=3 of=/dev/dev
 * dd conv=notrunc bs=2 count=210 seek=45 if=handoff.bin of=/dev/dev
 */

// #define DEBUG_MARKER1	/* Insert markers in binary */
// #define DEBUG_START	/* Print entry addresses at start */
// #define DEBUG_LOADE	/* movw versus pop */
#define DEBUG_PNP	/* Scan for $PnP and show address */
#define DEBUG_PAK	/* Press Any Key before boot fail */
// #define DEBUG_ENTRY_REG	/* Store (manually as pusha is 80186) registers */
// #define DEBUG_FDT	/* Print the floppy descriptor table; INT 1Eh*/

#ifdef DEBUG_MARKER1
	.macro ASCII_MARKER1 s:vararg
	.ascii	\s
	.endm
#else	/* DEBUG_MARKER1 */
	.macro ASCII_MARKER1 s:vararg
	.endm
#endif	/* DEBUG_MARKER1 */

#ifdef DEBUG_LOADE
	.macro LOADE r:req, t:req
	movw	(es_\r), %\t
	.endm
#else	/* DEBUG_LOADE */
	.macro LOADE r:req, t:req
	popw %\t
	.endm
#endif	/* DEBUG_LOADE */

	.code16
	.text

entry		= 0x7c00
stack		= (entry)
e_start		= (stack)
e_ax		= (e_start-2)
e_ss		= (e_ax-2)
e_sp		= (e_ss-2)
e_bot		= (e_ss)
/* Doubtful this will be used */
e0_beg		= (e_bot)
e0_ax		= (e0_beg-2)
e0_cx		= (e0_ax-2)
e0_dx		= (e0_cx-2)
e0_bx		= (e0_dx-2)
e0_sp		= (e0_bx-2)
e0_bp		= (e0_sp-2)
e0_si		= (e0_bp-2)
e0_di		= (e0_si-2)
e0_ds		= (e0_di-2)
e0_es		= (e0_ds-2)
e0_bot		= (e0_es)
es_beg		= (e0_bot)	/* Original register values from entry point */
es_di		= (es_beg-2)
es_es		= (es_di-2)
es_si		= (es_es-2)
es_ds		= (es_si-2)
es_bot		= (es_ds)

BIOS_page	= 0x462

int_1e		= (4*0x1e)
int_1e_seg	= (int_1e)
int_1e_off	= (int_1e+2)

	.globl	_start
_start:
	cli
#ifdef DEBUG_ENTRY_REG
	movw	%ax, e_ax
	movw	%ss, e_ss
	movw	%sp, e_sp
#endif /* DEBUG_ENTRY_REG */
	xorw	%ax, %ax
	movw	%ax, %ss
#ifdef DEBUG_ENTRY_REG
	movw	$e0_beg, %sp
	/* pushaw */		/* 80186 */
	pushw	%ax
	pushw	%cx
	pushw	%dx
	pushw	%bx
	pushw	%sp
	pushw	%bp
	pushw	%si
	pushw	%di
	pushw	%ds
	pushw	%es
#else /* DEBUG_ENTRY_REG */
	movw	$es_beg, %sp
#endif /* DEBUG_ENTRY_REG */
	pushw	%di		/* es:di -> $PnP header */
	pushw	%es
	pushw	%si
	pushw	%ds
	sti
	cld
	pushw	%cs
	popw	%ds

#ifdef DEBUG_START
	pushw	%dx
	call	crlf
	movw	$(_start),%dx	/* 0x0600 mbr.ld .text address */
	call	wrhexw
	call	crlf
	call	caddr
caddr:
	popw	%dx
	subw	$(caddr - _start), %dx
	call	wrhexw
	call	crlf
	popw	%dx
#endif	/* DEBUG_START */

	/* write DL */
pr_dl:	call	wrstr
	.ascii	"DL: \0"
	call	wrhexb
	/* DS */
pr_ds:	call	wrstr
	.ascii	"  DS: \0"
	LOADE	ds, dx
	pushw	%dx
	popw	%es
	call	wrhexw
	/* SI */
pr_si:	call	wrstr
	.ascii	"  SI: \0"
	LOADE	si, dx
	pushw	%dx
	popw	%di
	call	wrhexw
	call	crlf
	/* DS:SI */
	movw	$16, %cx
	call	wrhexbses
	call	crlf

	/* ES */
pr_es:	call	wrstr
	.ascii	"ES: \0"
	LOADE	es, dx
	pushw	%dx
	popw	%es
	call	wrhexw
pr_di:	call	wrstr
	.ascii	"  DI: \0"
	LOADE	di, dx
	pushw	%dx
	popw	%di
	call	wrhexw
	call	crlf
	/* ES:DI */	/* %es:0(%di) */
	movw	$4, %cx
	call	wrhexbses

#ifdef DEBUG_PNP
	subw	$4, %si
	es lodsw
	cmpw	$0x5024, %ax
	jne	scn_pnp
	es lodsw
	cmpw	$0x506E, %ax
	jne	scn_pnp
	call	wrstr
	.ascii	" =$PnP\0"
scn_pnp:
	call	crlf
	/* $PnP Scan */
	movw	$0xf000, %dx
	pushw	%dx
	popw	%es
	movw	$0, %si
	movw	$0x1000, %cx
	/* 0x506E5024 */
	movw	$0x5024, %dx
	movw	$0x506E, %bx
ch_pnp:	es lodsw	/* Check for $PnP */
	cmpw	%dx, %ax
	jne	ch_pnp_l
	es lodsw
	cmpw	%bx, %ax
	je	pr_pnp
ch_pnp_l:		/* Check $PnP failed; loop to next address */
	addw	$14, %si
	andw	$0xFFF0, %si
	loopw	ch_pnp
	jmp	pnp_end
pr_pnp:
	pushw	%si
	call	wrstr
	.ascii	"$PnP-\0"
	movw	%es, %dx
	call	wrhexw
	movb	$':, %al
	call	wrchr
	popw	%dx
	andw	$0xFFF0, %dx
	call	wrhexw
#endif	/* DEBUG_PNP */
	call	crlf
pnp_end:

#ifdef DEBUG_FDT
	/* INT 1Eh: Floppy Parameter Table Pointer */
pr_1e:	call	wrstr
	.ascii	"INT 1Eh: \0"
	mov	$int_1e,%bx
	les	(%bx),%di
	pushw	%es
	popw	%dx
	call	wrhexw
	movb	$':, %al
	call	wrchr
	pushw	%di
	popw	%dx
	call	wrhexw
	call	crlf
	/* [INT 1Eh] */
	movw	$14, %cx
	call	wrhexbses
	call	crlf
#endif	/* DEBUG_FDT */

end:
	jmp	bootfail

	ASCII_MARKER1	"wc"
wrchr:
	movb	$0x0e, %ah
	movb	(BIOS_page), %bh
	movb	$0x07, %bl
	int	$0x10		/* May destroy %bp */
	ret

	ASCII_MARKER1	"ws"
wrstr:
	pop	%si
wrstr_l:
	lodsb
	cmpb	$0, %al
	je	wrstr_d
	call	wrchr
	jmp	wrstr_l
wrstr_d:
	push	%si
	ret

crlf:
	call	wrstr
	.ascii	"\r\n\0"
	ret

	ASCII_MARKER1	"hx"
wrhexn:
	and	$0x0F, %al
	cmpb	$10, %al
	jae	.alph
	addb	$'0, %al
	jmp	.wc
.alph:
	addb	$('A - 10), %al
.wc:
	call wrchr
	ret

wrhexb:
	pushw	%cx
	movb	%dl, %al
	pushw	%ax
	movb	$4, %cl
	rorw	%cl, %ax
	call	wrhexn
	popw	%ax
	call	wrhexn
	popw	%cx
	ret

wrhexw:
	pushw	%cx
	movb	$8, %cl
	rorw	%cl, %dx
	call wrhexb
	rorw	%cl, %dx
	call wrhexb
	popw	%cx
	ret

	ASCII_MARKER1	"HE"
wrhexbses:
	pushw	%di
	popw	%si
wrhexbses_l:
	movb	$' , %al
	call	wrchr
	es lodsb
	movw	%ax, %dx
	call	wrhexb
	loop	wrhexbses_l
	ret

data:
	ASCII_MARKER1	"bf"
bootfail:
#ifdef DEBUG_PAK
	call wrstr
	.ascii	"\r\n\r\nPress any key\r\n\0"
	xor	%ax, %ax
	int	$0x16
#endif
	int	$0x18		/* Boot failure */
die:
	hlt
	jmp	die
