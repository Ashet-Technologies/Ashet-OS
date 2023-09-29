/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Erwan Velu - All Rights Reserved
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * -----------------------------------------------------------------------
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <syslinux/pxe.h>
#include <syslinux/config.h>

#include "hdt-cli.h"
#include "hdt-common.h"

void main_show_syslinux(int argc __unused, char **argv __unused,
			struct s_hardware *hardware)
{
    reset_more_printf();
    more_printf("SYSLINUX\n");
    more_printf(" Bootloader : %s\n", hardware->syslinux_fs);
    more_printf(" Version    : %s\n", hardware->sv->version_string);
    more_printf(" Version    : %u\n", hardware->sv->version);
    more_printf(" Max API    : %u\n", hardware->sv->max_api);
    more_printf(" Copyright  : %s\n", hardware->sv->copyright_string);
}

struct cli_module_descr syslinux_show_modules = {
    .modules = NULL,
    .default_callback = main_show_syslinux,
};

struct cli_mode_descr syslinux_mode = {
    .mode = SYSLINUX_MODE,
    .name = CLI_SYSLINUX,
    .default_modules = NULL,
    .show_modules = &syslinux_show_modules,
    .set_modules = NULL,
};
