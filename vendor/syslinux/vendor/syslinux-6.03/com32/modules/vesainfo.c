/*
 * vesainfo.c
 *
 * Dump information about what VESA graphics modes are supported.
 */

#include <string.h>
#include <stdio.h>
#include <console.h>
#include <com32.h>
#include <inttypes.h>
#include "../lib/sys/vesa/vesa.h"

/* Wait for a keypress */
static void wait_key(void)
{
    char ch;
    while (fread(&ch, 1, 1, stdin) == 0) ;
}

static void print_modes(void)
{
	static com32sys_t rm;
	struct vesa_general_info *gi;
	struct vesa_mode_info *mi;
	uint16_t mode, *mode_ptr;
	int lines;

	struct vesa_info *vesa;

	vesa = lmalloc(sizeof(*vesa));
	if (!vesa) {
		printf("vesainfo.c32: fail in lmalloc\n");
		return;
	}
	gi = &vesa->gi;
	mi = &vesa->mi;

        memset(&rm, 0, sizeof rm);
	gi->signature = VBE2_MAGIC;	/* Get VBE2 extended data */
	rm.eax.w[0] = 0x4F00;	/* Get SVGA general information */
	rm.edi.w[0] = OFFS(gi);
	rm.es = SEG(gi);
	__intcall(0x10, &rm, &rm);

    if (rm.eax.w[0] != 0x004F) {
	printf("No VESA BIOS detected\n");
	goto exit;
    } else if (gi->signature != VESA_MAGIC) {
	printf("VESA information structure has bad magic, trying anyway...\n");
    }

    printf("VBE version %d.%d\n"
	   "Mode   attrib h_res v_res bpp layout rpos gpos bpos\n",
	   (gi->version >> 8) & 0xff, gi->version & 0xff);

    lines = 1;

    mode_ptr = GET_PTR(gi->video_mode_ptr);

    while ((mode = *mode_ptr++) != 0xFFFF) {
	if (++lines >= 23) {
	    wait_key();
	    lines = 0;
	}

        memset(&rm, 0, sizeof rm);
	rm.eax.w[0] = 0x4F01;	/* Get SVGA mode information */
	rm.ecx.w[0] = mode;
	rm.edi.w[0] = OFFS(mi);
	rm.es = SEG(mi);
	__intcall(0x10, &rm, &rm);

	/* Must be a supported mode */
	if (rm.eax.w[0] != 0x004f)
	    continue;

	printf("0x%04x 0x%04x %5u %5u %3u %6u %4u %4u %4u\n",
	       mode, mi->mode_attr, mi->h_res, mi->v_res, mi->bpp,
	       mi->memory_layout, mi->rpos, mi->gpos, mi->bpos);
    }

exit:
	lfree(vesa);
	return;
}

int main(int argc __unused, char **argv __unused)
{
    print_modes();
    return 0;
}
