#include <unistd.h>
#include <errno.h>
#include "file.h"

int getscreensize(int fd, int *rows, int *cols)
{
    struct file_info *fp = &__file_info[fd];

    if (fd >= NFILES || !fp->iop) {
	errno = EBADF;
	return -1;
    }

    *rows = fp->o.rows;
    *cols = fp->o.cols;

    if (!*rows || !*cols) {
	errno = ENOTTY;
	return -1;
    }

    return 0;
}
