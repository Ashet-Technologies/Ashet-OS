/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
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
 * solaris.c
 *
 * Solaris DHCP hack
 *
 * Solaris uses a nonstandard hack to pass DHCP information from a netboot.
 */

#include "mboot.h"
#include <syslinux/pxe.h>
#include <syslinux/config.h>

bool kernel_is_solaris(const Elf32_Ehdr *eh)
{
    return eh->e_ident[EI_OSABI] == 6;	/* ABI == Solaris */
}

void mboot_solaris_dhcp_hack(void)
{
    void *dhcpdata;
    size_t dhcplen;

    if (syslinux_derivative_info()->c.filesystem != SYSLINUX_FS_PXELINUX)
	return;
    
    if (!pxe_get_cached_info(PXENV_PACKET_TYPE_DHCP_ACK, &dhcpdata, &dhcplen)) {
	mbinfo.drives_addr = map_data(dhcpdata, dhcplen, 4, 0);
	if (mbinfo.drives_addr) {
	    mbinfo.drives_length = dhcplen;
	    mbinfo.boot_device = 0x20ffffff;
	    mbinfo.flags =
		(mbinfo.flags & ~MB_INFO_DRIVE_INFO) | MB_INFO_BOOTDEV;
	}
    }
}
