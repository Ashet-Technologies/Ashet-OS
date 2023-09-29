#include "fs.h"

void generic_close_file(struct file *file)
{
    if (file->inode) {
	file->offset = 0;
	put_inode(file->inode);
    }
}
