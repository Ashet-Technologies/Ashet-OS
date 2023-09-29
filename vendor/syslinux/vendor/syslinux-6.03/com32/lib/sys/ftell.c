/*
 * sys/ftell.c
 *
 * We can't seek, but we can at least tell...
 */

#include <stdio.h>
#include "sys/file.h"

long ftell(FILE * stream)
{
    int fd = fileno(stream);
    struct file_info *fp = &__file_info[fd];

    return fp->i.offset;
}
