/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Pierre-Alexandre Meyer - All Rights Reserved
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

#include <string.h>
#include <vpd/vpd.h>

#include "hdt-cli.h"
#include "hdt-common.h"

void main_show_vpd(int argc __unused, char **argv __unused,
		   struct s_hardware *hardware)
{
    reset_more_printf();

    if (!hardware->is_vpd_valid) {
	more_printf("No VPD structure detected.\n");
	return;
    }

    more_printf("VPD present at address : %s\n", hardware->vpd.base_address);
    if (strlen(hardware->vpd.bios_build_id) > 0)
	more_printf("Bios Build ID                 : %s\n",
		    hardware->vpd.bios_build_id);
    if (strlen(hardware->vpd.bios_release_date) > 0)
	more_printf("Bios Release Date             : %s\n",
		    hardware->vpd.bios_release_date);
    if (strlen(hardware->vpd.bios_version) > 0)
	more_printf("Bios Version                  : %s\n",
		    hardware->vpd.bios_version);
    if (strlen(hardware->vpd.default_flash_filename) > 0)
	more_printf("Default Flash Filename        : %s\n",
		    hardware->vpd.default_flash_filename);
    if (strlen(hardware->vpd.box_serial_number) > 0)
	more_printf("Box Serial Number             : %s\n",
		    hardware->vpd.box_serial_number);
    if (strlen(hardware->vpd.motherboard_serial_number) > 0)
	more_printf("Motherboard Serial Number     : %s\n",
		    hardware->vpd.motherboard_serial_number);
    if (strlen(hardware->vpd.machine_type_model) > 0)
	more_printf("Machine Type/Model            : %s\n",
		    hardware->vpd.machine_type_model);
}

struct cli_module_descr vpd_show_modules = {
    .modules = NULL,
    .default_callback = main_show_vpd,
};

struct cli_mode_descr vpd_mode = {
    .mode = VPD_MODE,
    .name = CLI_VPD,
    .default_modules = NULL,
    .show_modules = &vpd_show_modules,
    .set_modules = NULL,
};
