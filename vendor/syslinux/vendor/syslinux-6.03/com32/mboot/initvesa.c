/* ----------------------------------------------------------------------- *
 *
 *   Copyright 1999-2008 H. Peter Anvin - All Rights Reserved
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
 * initvesa.c
 *
 * Query the VESA BIOS and select a 640x480x32 mode with local mapping
 * support, if one exists.
 */

#include <inttypes.h>
#include <com32.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <graphics.h>

#include "vesa.h"
#include "mboot.h"

struct vesa_info vesa_info;

void set_graphics_mode(const struct multiboot_header *mbh,
		       struct multiboot_info *mbi)
{
    com32sys_t rm;
    uint16_t mode, bestmode, *mode_ptr;
    struct vesa_general_info *gi;
    struct vesa_mode_info *mi;
    int pxf, bestpxf;
    int wantx, wanty;
    int err, besterr;
    bool better;
    addr_t viaddr;

    /* Only do this if requested by the OS image */
    if (!(mbh->flags & MULTIBOOT_VIDEO_MODE) || mbh->mode_type != 0)
	return;

    gi = lmalloc(sizeof *gi);
    if (!gi)
	return;

    mi = lmalloc(sizeof *mi);
    if (!mi)
	goto out;

    memset(&rm, 0, sizeof rm);
    memset(gi, 0, sizeof *gi);

    gi->signature = VBE2_MAGIC;	/* Get VBE2 extended data */
    rm.eax.w[0] = 0x4F00;	/* Get SVGA general information */
    rm.edi.w[0] = OFFS(gi);
    rm.es = SEG(gi);
    __intcall(0x10, &rm, &rm);

    if (rm.eax.w[0] != 0x004F)
	goto out;		/* Function call failed */
    if (gi->signature != VESA_MAGIC)
	goto out;		/* No magic */
    if (gi->version < 0x0102)
	goto out;		/* VESA 1.2+ required */

    memcpy(&vesa_info.gi, gi, sizeof *gi);

    /* Search for a suitable mode with a suitable color and memory model... */

    mode_ptr = GET_PTR(gi->video_mode_ptr);
    bestmode = 0;
    bestpxf = 0;
    wantx = mbh->width  ? mbh->width  : 0xffff;
    wanty = mbh->height ? mbh->height : 0xffff;
    besterr = wantx + wanty;

    while ((mode = *mode_ptr++) != 0xFFFF) {
	mode &= 0x1FF;		/* The rest are attributes of sorts */

        memset(&rm, 0, sizeof rm);
	memset(mi, 0, sizeof *mi);
	rm.eax.w[0] = 0x4F01;	/* Get SVGA mode information */
	rm.ecx.w[0] = mode;
	rm.edi.w[0] = OFFS(mi);
	rm.es = SEG(mi);
	__intcall(0x10, &rm, &rm);

	/* Must be a supported mode */
	if (rm.eax.w[0] != 0x004f)
	    continue;

	/* Must be an LFB color graphics mode supported by the hardware.

	   The bits tested are:
	   7 - linear frame buffer
	   4 - graphics mode
	   3 - color mode
	   1 - mode information available (mandatory in VBE 1.2+)
	   0 - mode supported by hardware
	 */
	if ((mi->mode_attr & 0x009b) != 0x009b)
	    continue;

	/* We don't support multibank (interlaced memory) modes */
	/*
	 *  Note: The Bochs VESA BIOS (vbe.c 1.58 2006/08/19) violates the
	 * specification which states that banks == 1 for unbanked modes;
	 * fortunately it does report bank_size == 0 for those.
	 */
	if (mi->banks > 1 && mi->bank_size)
	    continue;

	/* Must either be a packed-pixel mode or a direct color mode
	   (depending on VESA version ); must be a supported pixel format */

	if (mi->bpp == 32 &&
	    (mi->memory_layout == 4 ||
	     (mi->memory_layout == 6 && mi->rpos == 16 && mi->gpos == 8 &&
	      mi->bpos == 0)))
	    pxf = 32;
	else if (mi->bpp == 24 &&
		 (mi->memory_layout == 4 ||
		  (mi->memory_layout == 6 && mi->rpos == 16 && mi->gpos == 8 &&
		   mi->bpos == 0)))
	    pxf = 24;
	else if (mi->bpp == 16 &&
		 (mi->memory_layout == 4 ||
		  (mi->memory_layout == 6 && mi->rpos == 11 && mi->gpos == 5 &&
		   mi->bpos == 0)))
	    pxf = 16;
	else if (mi->bpp == 15 &&
		 (mi->memory_layout == 4 ||
		  (mi->memory_layout == 6 && mi->rpos == 10 && mi->gpos == 5 &&
		   mi->bpos == 0)))
	    pxf = 15;
	else
	    continue;

	better = false;
	err = abs(mi->h_res - wantx) + abs(mi->v_res - wanty);

#define IS_GOOD(mi, bestx, besty) \
	((mi)->h_res >= (bestx) && (mi)->v_res >= (besty))

	if (!bestpxf)
	    better = true;
	else if (!IS_GOOD(&vesa_info.mi, wantx, wanty) &&
		 IS_GOOD(mi, wantx, wanty))
	    /* This matches criteria, which the previous one didn't */
	    better = true;
	else if (IS_GOOD(&vesa_info.mi, wantx, wanty) &&
		 !IS_GOOD(mi, wantx, wanty))
	    /* This doesn't match criteria, and the previous one did */
	    better = false;
	else if (err < besterr)
	    better = true;
	else if (err == besterr && (pxf == (int)mbh->depth || pxf > bestpxf))
	    better = true;

	if (better) {
	    bestmode = mode;
	    bestpxf = pxf;
	    memcpy(&vesa_info.mi, mi, sizeof *mi);
	}
    }

    if (!bestpxf)
	goto out;		/* No mode found */

    mi = &vesa_info.mi;
    mode = bestmode;

    /* Now set video mode */
    memset(&rm, 0, sizeof rm);
    rm.eax.w[0] = 0x4F02;	/* Set SVGA video mode */
    mode |= 0x4000;		/* Request linear framebuffer */
    rm.ebx.w[0] = mode;
    __intcall(0x10, &rm, &rm);
    if (rm.eax.w[0] != 0x004F)
	goto out;		/* Failed to set mode */

    mbi->flags |= MB_INFO_VIDEO_INFO;
    mbi->vbe_mode = mode;
    viaddr = map_data(&vesa_info, sizeof vesa_info, 4, 0);
    mbi->vbe_control_info = viaddr + offsetof(struct vesa_info, gi);
    mbi->vbe_mode_info = viaddr + offsetof(struct vesa_info, mi);

    /* Get the VBE 2.x PM entry point if supported */
    rm.eax.w[0] = 0x4F0A;
    rm.ebx.w[0] = 0;
    __intcall(0x10, &rm, &rm);
    if (rm.eax.w[0] == 0x004F) {
	mbi->vbe_interface_seg = rm.es;
	mbi->vbe_interface_off = rm.edi.w[0];
	mbi->vbe_interface_len = rm.ecx.w[0];
    }

    /* In theory this should be:
     *
     * UsingVga = (mi->mode_attr & 4) ? 0x0007 : 0x000f;
     *
     * However, that would assume all systems that claim to handle text
     * output in VESA modes actually do that...
     */
    graphics_using_vga(0x0F, vesa_info.mi.h_res, vesa_info.mi.v_res);

out:
    lfree(mi);
    lfree(gi);
}
