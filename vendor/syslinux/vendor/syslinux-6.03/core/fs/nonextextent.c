#include "fs.h"

/*
 * Use this routine for the next_extent() pointer when we never should
 * be calling next_extent(), e.g. iso9660.
 */
int no_next_extent(struct inode *inode, uint32_t lstart)
{
    (void)inode;
    (void)lstart;

    return -1;
}
