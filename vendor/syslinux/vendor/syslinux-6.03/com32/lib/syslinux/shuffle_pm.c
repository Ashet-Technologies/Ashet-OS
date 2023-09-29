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
 * shuffle_pm.c
 *
 * Shuffle and boot to protected mode code
 */

#include <inttypes.h>
#include <syslinux/movebits.h>
#include <syslinux/bootpm.h>

int syslinux_shuffle_boot_pm(struct syslinux_movelist *fraglist,
			     struct syslinux_memmap *memmap,
			     uint16_t bootflags, struct syslinux_pm_regs *regs)
{
    uint8_t handoff_code[9 * 5], *p;
    const uint32_t *rp;
    int i, rv;
    struct syslinux_memmap *tmap;
    addr_t regstub, stublen;

    tmap = syslinux_target_memmap(fraglist, memmap);
    if (!tmap)
	return -1;

    regstub = 0x800;		/* Locate anywhere above this point */
    stublen = sizeof handoff_code;
    rv = syslinux_memmap_find_type(tmap, SMT_FREE, &regstub, &stublen, 1);
    syslinux_free_memmap(tmap);
    if (rv)
	return -1;

    /* Build register-setting stub */
    p = handoff_code;
    rp = (const uint32_t *)regs;
    for (i = 0; i < 8; i++) {
	*p = 0xb8 + i;		/* MOV gpr,imm32 */
	*(uint32_t *) (p + 1) = *rp++;
	p += 5;
    }
    *p = 0xe9;			/* JMP */
    *(uint32_t *) (p + 1) = regs->eip - regstub - sizeof handoff_code;

    /* Add register-setting stub to shuffle list */
    if (syslinux_add_movelist(&fraglist, regstub, (addr_t) handoff_code,
			      sizeof handoff_code))
	return -1;

    return syslinux_do_shuffle(fraglist, memmap, regstub, 1, bootflags);
}
