/*
 *   Copyright 1994-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *  Boston MA 02111-1307, USA; either version 2 of the License, or
 *  (at your option) any later version; incorporated herein by reference.
 */

#include <syslinux/video.h>
#include "pxe.h"
#include <com32.h>

#define LOCALBOOT_MSG	"Booting from local disk..."

extern void local_boot16(void);

/*
 * Boot to the local disk by returning the appropriate PXE magic.
 * AX contains the appropriate return code.
 */
__export void local_boot(uint16_t ax)
{
    com32sys_t ireg;
    memset(&ireg, 0, sizeof ireg);

    syslinux_force_text_mode();

    writestr(LOCALBOOT_MSG);
    crlf();

    /* Restore the environment we were called with */
    reset_pxe();

    cleanup_hardware();

    ireg.eax.w[0] = ax;
    call16(local_boot16, &ireg, NULL);
}
