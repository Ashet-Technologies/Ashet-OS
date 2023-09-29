#ifndef _H_SYSLXCOM_
#define _H_SYSLXCOM_

#include "syslinux.h"

extern const char *program;
ssize_t xpread(int fd, void *buf, size_t count, off_t offset);
ssize_t xpwrite(int fd, const void *buf, size_t count, off_t offset);
void clear_attributes(int fd);
void set_attributes(int fd);
int sectmap(int fd, sector_t *sectors, int nsectors);
int syslinux_already_installed(int dev_fd);

#endif
