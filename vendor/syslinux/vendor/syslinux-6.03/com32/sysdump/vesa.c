#include <string.h>
#include <stdio.h>
#include <lib/sys/vesa/vesa.h>
#include "sysdump.h"

void dump_vesa_tables(struct upload_backend *be)
{
    com32sys_t rm;
    struct vesa_info *vip;
    struct vesa_general_info *gip, gi;
    struct vesa_mode_info *mip, mi;
    uint16_t mode, *mode_ptr;
    char modefile[64];

    printf("Scanning VESA BIOS... ");

    /* Allocate space in the bounce buffer for these structures */
    vip = lmalloc(sizeof *vip);
    gip = &vip->gi;
    mip = &vip->mi;

    memset(&rm, 0, sizeof rm);
    memset(gip, 0, sizeof *gip);

    gip->signature = VBE2_MAGIC;	/* Get VBE2 extended data */
    rm.eax.w[0] = 0x4F00;		/* Get SVGA general information */
    rm.edi.w[0] = OFFS(gip);
    rm.es = SEG(gip);
    __intcall(0x10, &rm, &rm);
    memcpy(&gi, gip, sizeof gi);

    if (rm.eax.w[0] != 0x004F)
	return;		/* Function call failed */
    if (gi.signature != VESA_MAGIC)
	return;		/* No magic */

    cpio_mkdir(be, "vesa");

    cpio_writefile(be, "vesa/global.bin", &gi, sizeof gi);

    mode_ptr = GET_PTR(gi.video_mode_ptr);
    while ((mode = *mode_ptr++) != 0xFFFF) {
	memset(mip, 0, sizeof *mip);
        memset(&rm, 0, sizeof rm);
	rm.eax.w[0] = 0x4F01;	/* Get SVGA mode information */
	rm.ecx.w[0] = mode;
	rm.edi.w[0] = OFFS(mip);
	rm.es = SEG(mip);
	__intcall(0x10, &rm, &rm);

	/* Must be a supported mode */
	if (rm.eax.w[0] != 0x004f)
	    continue;

	memcpy(&mi, mip, sizeof mi);

	sprintf(modefile, "vesa/mode%04x.bin", mode);
	cpio_writefile(be, modefile, &mi, sizeof mi);
    }

    lfree(vip);
    printf("done.\n");
}
