/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2003-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
 *   Copyright 2010 Shao Miller
 *   Copyright 2010-2012 Michal Soltys
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#ifndef COM32_CHAIN_CHAIN_H
#define COM32_CHAIN_CHAIN_H

#include <syslinux/movebits.h>

struct data_area {
    void *data;
    addr_t base;
    addr_t size;
};

#endif

/* vim: set ts=8 sts=4 sw=4 noet: */
