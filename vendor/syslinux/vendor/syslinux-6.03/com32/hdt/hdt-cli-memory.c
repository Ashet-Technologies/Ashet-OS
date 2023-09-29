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

#include <memory.h>

#include "hdt-cli.h"
#include "hdt-common.h"

static void show_memory_e820(int argc __unused, char **argv __unused,
			     struct s_hardware *hardware __unused)
{
    struct e820entry map[E820MAX];
    unsigned long memsize = 0;
    int count = 0;
    char type[14];

    detect_memory_e820(map, E820MAX, &count);
    memsize = memsize_e820(map, count);
    reset_more_printf();
    more_printf("Detected RAM                       : %lu MiB (%lu KiB)\n",
		(memsize + (1 << 9)) >> 10, memsize);
    more_printf("BIOS-provided physical RAM e820 map:\n");
    for (int i = 0; i < count; i++) {
	get_type(map[i].type, type, 14);
	more_printf("%016llx - %016llx %016llx (%s)\n",
		    map[i].addr, map[i].size, map[i].addr + map[i].size,
		    remove_spaces(type));
    }
    struct e820entry nm[E820MAX];

    /* Clean up, adjust and copy the BIOS-supplied E820-map. */
    int nr = sanitize_e820_map(map, nm, count);

    more_printf("\n");
    more_printf("Sanitized e820 map:\n");
    for (int i = 0; i < nr; i++) {
	get_type(nm[i].type, type, 14);
	more_printf("%016llx - %016llx %016llx (%s)\n",
		    nm[i].addr, nm[i].size, nm[i].addr + nm[i].size,
		    remove_spaces(type));
    }
}

static void show_memory_e801(int argc __unused, char **argv __unused,
			     struct s_hardware *hardware __unused)
{
    int mem_low, mem_high = 0;

    reset_more_printf();
    if (detect_memory_e801(&mem_low, &mem_high)) {
	more_printf("e801 bogus!\n");
    } else {
	more_printf("Detected RAM : %d MiB(%d KiB)\n",
		    (mem_low >> 10) + (mem_high >> 4),
		    mem_low + (mem_high << 6));
	more_printf("e801 details : %d Kb (%d MiB) - %d Kb (%d MiB)\n", mem_low,
		    mem_low >> 10, mem_high << 6, mem_high >> 4);
    }
}

static void show_memory_88(int argc __unused, char **argv __unused,
			   struct s_hardware *hardware __unused)
{
    int mem_size = 0;

    reset_more_printf();
    if (detect_memory_88(&mem_size)) {
	more_printf("8800h bogus!\n");
    } else {
	more_printf("8800h memory size: %d Kb (%d MiB)\n", mem_size,
		    mem_size >> 10);
    }
}

struct cli_callback_descr list_memory_show_modules[] = {
    {
     .name = "e820",
     .exec = show_memory_e820,
     .nomodule=false,
     },
    {
     .name = "e801",
     .exec = show_memory_e801,
     .nomodule=false,
     },
    {
     .name = "88",
     .exec = show_memory_88,
     .nomodule=false,
     },
    {
     .name = CLI_DMI_MEMORY_BANK,
     .exec = show_dmi_memory_bank,
     .nomodule=false,
     },
    {
     .name = NULL,
     .exec = NULL,
     .nomodule=false,
     },
};

struct cli_module_descr memory_show_modules = {
    .modules = list_memory_show_modules,
    .default_callback = show_dmi_memory_modules,
};

struct cli_mode_descr memory_mode = {
    .mode = MEMORY_MODE,
    .name = CLI_MEMORY,
    .default_modules = NULL,
    .show_modules = &memory_show_modules,
    .set_modules = NULL,
};
