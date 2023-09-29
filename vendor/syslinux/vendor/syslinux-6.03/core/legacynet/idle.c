/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2008 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <stdio.h>
#include <string.h>
#include <core.h>
#include <fs.h>
#include <minmax.h>
#include <sys/cpu.h>
#include "pxe.h"

static int pxe_idle_poll(void)
{
    static __lowmem char junk_pkt[PKTBUF_SIZE];
    static __lowmem t_PXENV_UDP_READ read_buf;

    memset(&read_buf, 0, sizeof read_buf);

    read_buf.src_ip  = 0;	 /* Any destination */
    read_buf.dest_ip = IPInfo.myip;
    read_buf.s_port  = 0;	 /* Any source port */
    read_buf.d_port  = htons(9); /* Discard port (not used...) */
    read_buf.buffer_size = sizeof junk_pkt;
    read_buf.buffer  = FAR_PTR(junk_pkt);

    pxe_call(PXENV_UDP_READ, &read_buf);

    return 0;
}

static uint32_t pxe_detect_nic_type(void)
{
    static __lowmem t_PXENV_UNDI_GET_NIC_TYPE nic_type;

    if (pxe_call(PXENV_UNDI_GET_NIC_TYPE, &nic_type))
	return -1;		/* Unknown NIC */

    if (nic_type.NicType != PCI_NIC && nic_type.NicType != CardBus_NIC)
	return -1;		/* Not a PCI NIC */

    /*
     * Return VID:DID as a single number, with the VID in the high word
     * -- this is opposite from the usual order, but it makes it easier to
     * enforce that the table is sorted.
     */
    return (nic_type.info.pci.Vendor_ID << 16) + nic_type.info.pci.Dev_ID;
}

#define PCI_DEV(vid, did)	(((vid) << 16) + (did))

/* This array should be sorted!! */
static const uint32_t pxe_need_idle_drain[] =
{
    /*
     * Older Broadcom NICs: they need receive calls on idle to avoid
     * FIFO stalls.
     */
    PCI_DEV(0x14e4, 0x1659),	/* BCM5721 */
    PCI_DEV(0x14e4, 0x165a),	/* BCM5722 */
    PCI_DEV(0x14e4, 0x165b),	/* BCM5723 */
    PCI_DEV(0x14e4, 0x1668),	/* BCM5714 */
    PCI_DEV(0x14e4, 0x1669),	/* BCM5714S */
    PCI_DEV(0x14e4, 0x166a),	/* BCM5780 */
    PCI_DEV(0x14e4, 0x1673),	/* BCM5755M */
    PCI_DEV(0x14e4, 0x1674),	/* BCM5756ME */
    PCI_DEV(0x14e4, 0x1678),	/* BCM5715 */
    PCI_DEV(0x14e4, 0x1679),	/* BCM5715S */
    PCI_DEV(0x14e4, 0x167b),	/* BCM5755 */
};

void pxe_idle_init(void)
{
    uint32_t dev_id = pxe_detect_nic_type();
    int l, h;
    bool found;

    l = 0;
    h = sizeof pxe_need_idle_drain / sizeof pxe_need_idle_drain[0] - 1;

    found = false;
    while (h >= l) {
	int x = (l+h) >> 1;
	uint32_t id = pxe_need_idle_drain[x];

	if (id == dev_id) {
	    found = true;
	    break;
	} else if (id < dev_id) {
	    l = x+1;
	} else {
	    h = x-1;
	}
    }

    if (found)
	idle_hook_func = pxe_idle_poll;
}

void pxe_idle_cleanup(void)
{
    idle_hook_func = NULL;
}
