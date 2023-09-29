/*
 * fdopendir.c
 */

#include <dirent.h>
#include <stdio.h>
#include <errno.h>

DIR *fdopendir(int __fd)
{
    (void)__fd;

    errno = ENOSYS;
    return NULL;
}
