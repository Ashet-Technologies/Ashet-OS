/*
 * fopendev.c
 */

#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>

FILE *fopendev(const struct dev_info * dev, const char *mode)
{
    int flags = O_RDONLY;
    int plus = 0;
    int fd;

    while (*mode) {
	switch (*mode) {
	case 'r':
	    flags = O_RDONLY;
	    break;
	case 'w':
	    flags = O_WRONLY | O_CREAT | O_TRUNC;
	    break;
	case 'a':
	    flags = O_WRONLY | O_CREAT | O_APPEND;
	    break;
	case '+':
	    plus = 1;
	    break;
	}
	mode++;
    }

    if (plus) {
	flags = (flags & ~(O_RDONLY | O_WRONLY)) | O_RDWR;
    }

    fd = opendev(file, flags);

    if (fd < 0)
	return NULL;
    else
	return fdopen(fd, mode);
}
