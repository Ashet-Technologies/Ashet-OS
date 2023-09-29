/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Shao Miller - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * eltorito.c
 *
 * EDD-4 El Torito structures and debugging routines
 */

#include <stdint.h>
#include "memdisk.h"
#include "conio.h"
#include "eltorito.h"

#ifdef DBG_ELTORITO
void eltorito_dump(uint32_t image)
{
    printf("-- El Torito dump --\n", image);

    /* BVD starts at sector 17. */
    struct edd4_bvd *bvd = (struct edd4_bvd *)(image + 17 * 2048);

    printf("bvd.boot_rec_ind: 0x%02x\n", bvd->boot_rec_ind);
    printf("bvd.iso9660_id: %c%c%c%c%c\n", bvd->iso9660_id[0],
	   bvd->iso9660_id[1], bvd->iso9660_id[2], bvd->iso9660_id[3],
	   bvd->iso9660_id[4]);
    printf("bvd.ver: 0x%02x\n", bvd->ver);
    printf("bvd.eltorito: %s\n", bvd->eltorito);
    printf("bvd.boot_cat: 0x%08x\n", bvd->boot_cat);

    struct edd4_bootcat *boot_cat =
	(struct edd4_bootcat *)(image + bvd->boot_cat * 2048);

    printf("boot_cat.validation_entry\n");
    printf("  .header_id: 0x%02x\n", boot_cat->validation_entry.header_id);
    printf("  .platform_id: 0x%02x\n", boot_cat->validation_entry.platform_id);
    printf("  .id_string: %s\n", boot_cat->validation_entry.id_string);
    printf("  .checksum: 0x%04x\n", boot_cat->validation_entry.checksum);
    printf("  .key55: 0x%02x\n", boot_cat->validation_entry.key55);
    printf("  .keyAA: 0x%02x\n", boot_cat->validation_entry.keyAA);
    printf("boot_cat.initial_entry\n");
    printf("  .header_id: 0x%02x\n", boot_cat->initial_entry.header_id);
    printf("  .media_type: 0x%02x\n", boot_cat->initial_entry.media_type);
    printf("  .load_seg: 0x%04x\n", boot_cat->initial_entry.load_seg);
    printf("  .system_type: 0x%02x\n", boot_cat->initial_entry.system_type);
    printf("  .sect_count: %d\n", boot_cat->initial_entry.sect_count);
    printf("  .load_block: 0x%08x\n", boot_cat->initial_entry.load_block);
}
#endif
