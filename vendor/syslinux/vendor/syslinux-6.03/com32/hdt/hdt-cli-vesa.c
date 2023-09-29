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

#include "hdt-cli.h"
#include "hdt-common.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>

void main_show_vesa(int argc __unused, char **argv __unused,
		    struct s_hardware *hardware)
{
    reset_more_printf();
    if (hardware->is_vesa_valid == false) {
	more_printf("No VESA BIOS detected\n");
	return;
    }
    more_printf("VESA\n");
    more_printf(" Vesa version : %d.%d\n", hardware->vesa.major_version,
		hardware->vesa.minor_version);
    more_printf(" Vendor       : %s\n", hardware->vesa.vendor);
    more_printf(" Product      : %s\n", hardware->vesa.product);
    more_printf(" Product rev. : %s\n", hardware->vesa.product_revision);
    more_printf(" Software rev.: %d\n", hardware->vesa.software_rev);
    more_printf(" Memory (KB)  : %d\n", hardware->vesa.total_memory * 64);
    more_printf(" Modes        : %d\n", hardware->vesa.vmi_count);
}

static void show_vesa_modes(int argc __unused, char **argv __unused,
			    struct s_hardware *hardware)
{
    reset_more_printf();
    if (hardware->is_vesa_valid == false) {
	more_printf("No VESA BIOS detected\n");
	return;
    }
    more_printf(" ResH. x ResV x Bits : vga= : Vesa Mode\n");
    more_printf("----------------------------------------\n");

    for (int i = 0; i < hardware->vesa.vmi_count; i++) {
	struct vesa_mode_info *mi = &hardware->vesa.vmi[i].mi;
	/*
	 * Sometimes, vesa bios reports 0x0 modes.
	 * We don't need to display that ones.
	 */
	if ((mi->h_res == 0) || (mi->v_res == 0))
	    continue;
	more_printf("%5u %5u    %3u     %3d     0x%04x\n",
		    mi->h_res, mi->v_res, mi->bpp,
		    hardware->vesa.vmi[i].mode + 0x200,
		    hardware->vesa.vmi[i].mode);
    }
}

static void enable_vesa(int argc __unused, char **argv __unused,
			struct s_hardware *hardware)
{
    vesamode = true;
    max_console_lines = MAX_VESA_CLI_LINES;
    init_console(hardware);
}

static void disable_vesa(int argc __unused, char **argv __unused,
			 struct s_hardware *hardware)
{
    vesamode = false;
    max_console_lines = MAX_CLI_LINES;
    init_console(hardware);
}

struct cli_callback_descr list_vesa_show_modules[] = {
    {
     .name = CLI_MODES,
     .exec = show_vesa_modes,
     .nomodule=false,
     },
    {
     .name = NULL,
     .exec = NULL,
     .nomodule=false,
     },
};

struct cli_callback_descr list_vesa_commands[] = {
    {
     .name = CLI_ENABLE,
     .exec = enable_vesa,
     .nomodule=false,
     },
    {
     .name = CLI_DISABLE,
     .exec = disable_vesa,
     .nomodule=false,
     },

    {
     .name = NULL,
     .exec = NULL,
     .nomodule=false,
     },
};

struct cli_module_descr vesa_show_modules = {
    .modules = list_vesa_show_modules,
    .default_callback = main_show_vesa,
};

struct cli_module_descr vesa_commands = {
    .modules = list_vesa_commands,
    .default_callback = enable_vesa,
};

struct cli_mode_descr vesa_mode = {
    .mode = VESA_MODE,
    .name = CLI_VESA,
    .default_modules = &vesa_commands,
    .show_modules = &vesa_show_modules,
    .set_modules = NULL,
};
