#include <stdlib.h>
#include <string.h>

#include <disk/swsusp.h>
#include <disk/read.h>
#include <disk/geom.h>

/**
 * swsusp_check - check if a (swap) partition contains the swsusp signature
 * @drive_info:	driveinfo struct describing the disk containing the partition
 * @ptab;	Partition table of the partition
 **/
int swsusp_check(struct driveinfo *drive_info, struct part_entry *ptab)
{
    struct swsusp_header header_p;
    int offset;
    int found;

    /* Read first page of the swap device */
    offset = ptab->start_lba;
    if (read_sectors(drive_info, &header_p, offset, PAGE_SIZE / SECTOR) == -1) {
	return -1;
    } else {
	found = !memcmp(SWSUSP_SIG, header_p.sig, 10);
	return found;
    }
}
