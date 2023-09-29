#include <dprintf.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <klibc/compiler.h>
#include <core.h>
#include <fs.h>
#include <disk.h>
#include <ilog2.h>
#include <minmax.h>

#include <syslinux/firmware.h>

void getoneblk(struct disk *disk, char *buf, block_t block, int block_size)
{
    int sec_per_block = block_size / disk->sector_size;

    disk->rdwr_sectors(disk, buf, block * sec_per_block, sec_per_block, 0);
}

/*
 * Initialize the device structure.
 */
struct device * device_init(void *args)
{
    static struct device dev;

    dev.disk = firmware->disk_init(args);
    dev.cache_size = 128*1024;
    dev.cache_data = malloc(dev.cache_size);
    dev.cache_init = 0; /* Explicitly set cache as uninitialized */

    return &dev;
}
