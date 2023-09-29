/* ----------------------------------------------------------------------- *
 *
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
 * shuffle_rm.c
 *
 * Shuffle and boot to protected mode code
 */

#include <stdlib.h>
#include <inttypes.h>
#include <com32.h>
#include <string.h>
#include <syslinux/movebits.h>
#include <syslinux/bootrm.h>

enum gpr_index { R_AX, R_CX, R_DX, R_BX, R_SP, R_BP, R_SI, R_DI };
enum seg_index { R_ES, R_CS, R_SS, R_DS, R_FS, R_GS };

#define ST8(P,V)						\
  do {								\
    uint8_t *_p = (void *)(P);					\
    *_p++ = (V);						\
    (P) = (void *)_p;						\
  } while (0);
#define ST16(P,V)						\
  do {								\
    uint16_t *_p = (void *)(P);					\
    *_p++ = (V);						\
    (P) = (void *)_p;						\
  } while (0)
#define ST32(P,V)						\
  do {								\
    uint32_t *_p = (void *)(P);					\
    *_p++ = (V);						\
    (P) = (void *)_p;						\
  } while (0)

#define MOV_TO_SEG(P,S,R)					\
    ST16(P, 0xc08e + ((R) << 8) + ((S) << 11))
#define MOV_TO_R16(P,R,V)					\
  do {								\
    ST8(P, 0xb8 + (R));						\
    ST16(P, V);							\
  }  while (0)
#define MOV_TO_R32(P,R,V)					\
  do {								\
    ST16(P, 0xb866 + ((R) << 8));				\
    ST32(P, V);							\
  } while (0)

int syslinux_shuffle_boot_rm(struct syslinux_movelist *fraglist,
			     struct syslinux_memmap *memmap,
			     uint16_t bootflags, struct syslinux_rm_regs *regs)
{
    const struct syslinux_rm_regs_alt {
	uint16_t seg[6];
	uint32_t gpr[8];
	uint32_t csip;
	bool sti;
    } *rp;
    int i, rv;
    uint8_t handoff_code[8 + 5 * 5 + 8 * 6 + 1 + 5], *p;
    uint16_t off;
    struct syslinux_memmap *tmap;
    addr_t regstub, stublen;
    /* Assign GPRs for each sreg, don't use AX and SP */
    static const uint8_t gpr_for_seg[6] =
	{ R_CX, R_DX, R_BX, R_BP, R_SI, R_DI };

    tmap = syslinux_target_memmap(fraglist, memmap);
    if (!tmap)
	return -1;

    /*
     * Search for a good place to put the real-mode register stub.
     * We prefer it as low as possible above 0x800.  KVM barfs horribly
     * if we're not aligned to a paragraph boundary, so set the alignment
     * appropriately.
     */
    regstub = 0x800;
    stublen = sizeof handoff_code;
    rv = syslinux_memmap_find_type(tmap, SMT_FREE, &regstub, &stublen, 16);

    if (rv || (regstub > 0x100000 - sizeof handoff_code)) {
	/*
	 * Uh-oh.  This isn't real-mode accessible memory.
	 * It might be possible to do something insane here like
	 * putting the stub in the IRQ vectors, or in the 0x5xx segment.
	 * This code tries the 0x510-0x7ff range and hopes for the best.
	 */
	regstub = 0x510;	/* Try the 0x5xx segment... */
	stublen = sizeof handoff_code;
	rv = syslinux_memmap_find_type(tmap, SMT_FREE, &regstub, &stublen, 16);

	if (!rv && (regstub > 0x100000 - sizeof handoff_code))
	    rv = -1;		/* No acceptable memory found */
    }

    syslinux_free_memmap(tmap);
    if (rv)
	return -1;

    /* Build register-setting stub */
    p = handoff_code;
    rp = (const struct syslinux_rm_regs_alt *)regs;

    /* Set up GPRs with segment registers - don't use AX */
    for (i = 0; i < 6; i++) {
	if (i != R_CS)
	    MOV_TO_R16(p, gpr_for_seg[i], rp->seg[i]);
    }

    /* Actual transition to real mode */
    ST32(p, 0xeac0220f);	/* MOV CR0,EAX; JMP FAR */
    off = (p - handoff_code) + 4;
    ST16(p, off);		/* Offset */
    ST16(p, regstub >> 4);	/* Segment */

    /* Load SS and ESP immediately */
    MOV_TO_SEG(p, R_SS, R_BX);
    MOV_TO_R32(p, R_SP, rp->gpr[R_SP]);

    /* Load the other segments */
    MOV_TO_SEG(p, R_ES, R_CX);
    MOV_TO_SEG(p, R_DS, R_BP);
    MOV_TO_SEG(p, R_FS, R_SI);
    MOV_TO_SEG(p, R_GS, R_DI);

    for (i = 0; i < 8; i++) {
	if (i != R_SP)
	    MOV_TO_R32(p, i, rp->gpr[i]);
    }

    ST8(p, rp->sti ? 0xfb : 0xfa);	/* STI/CLI */

    ST8(p, 0xea);		/* JMP FAR */
    ST32(p, rp->csip);

    /* Add register-setting stub to shuffle list */
    if (syslinux_add_movelist(&fraglist, regstub, (addr_t) handoff_code,
			      sizeof handoff_code))
	return -1;

    return syslinux_do_shuffle(fraglist, memmap, regstub, 0, bootflags);
}
