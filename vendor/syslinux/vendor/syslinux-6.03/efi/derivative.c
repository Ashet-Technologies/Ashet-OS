/*
 * Copyright 2012-2014 Intel Corporation - All Rights Reserved
 */

#include <syslinux/config.h>

/*
 * IP information.  Note that the field are in the same order as the
 * Linux kernel expects in the ip= option.
 */
struct syslinux_ipinfo IPInfo;
uint16_t APIVer;		/* PXE API version found */

static enum syslinux_filesystem __filesystem;

void efi_derivative(enum syslinux_filesystem fs)
{
    __filesystem = fs;
}
__export void get_derivative_info(union syslinux_derivative_info *di)
{
	di->disk.filesystem = __filesystem;
}
