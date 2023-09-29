/* -----------------------------------------------------------------------
 *
 *   Copyright 1994-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <inttypes.h>
#include <com32.h>
#include <syslinux/pmapi.h>
#include "core.h"
#include "fs.h"

const struct com32_pmapi pm_api_vector =
{
    .__pmapi_size = sizeof(struct com32_pmapi),

    .lmalloc	= pmapi_lmalloc, /* Allocate low memory */
    .lfree	= free,		 /* Free low memory */

    .open_file	= open_file,
    .read_file	= pmapi_read_file,
    .close_file	= close_file,

    .opendir	= opendir,
    .readdir	= readdir,
    .closedir	= closedir,

    .idle	= __idle,
    .reset_idle	= reset_idle,

    .chdir	= chdir,
    .getcwd	= core_getcwd,

    .jiffies	= &__jiffies,
    .ms_timer	= &__ms_timer,

    .sysappend_count	= SYSAPPEND_MAX,
    .sysappend_strings	= sysappend_strings,
};
