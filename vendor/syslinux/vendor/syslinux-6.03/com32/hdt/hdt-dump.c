/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2011 Erwan Velu - All Rights Reserved
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
#include <ctype.h>
#include <getkey.h>
#include <syslinux/config.h>
#include "hdt-common.h"
#include "hdt-dump.h"

struct print_buf p_buf;

struct dump_option {
    char *flag;
    char *item;
};

char *get_value_from_option(struct s_hardware *hardware, char *option)
{
    struct dump_option dump_options[10];
    dump_options[0].flag = "%{m}";
    dump_options[0].item = hardware->pxe.mac_addr;

    dump_options[1].flag = "%{v}";
    dump_options[1].item = hardware->dmi.system.manufacturer;

    dump_options[2].flag = "%{p}";
    dump_options[2].item = hardware->dmi.system.product_name;

    dump_options[3].flag = "%{ba}";
    dump_options[3].item = hardware->dmi.base_board.asset_tag;

    dump_options[4].flag = "%{bs}";
    dump_options[4].item = hardware->dmi.base_board.serial;

    dump_options[5].flag = "%{ca}";
    dump_options[5].item = hardware->dmi.chassis.asset_tag;

    dump_options[6].flag = "%{cs}";
    dump_options[6].item = hardware->dmi.chassis.serial;

    dump_options[7].flag = "%{sk}";
    dump_options[7].item = hardware->dmi.system.sku_number;

    dump_options[8].flag = "%{ss}";
    dump_options[8].item = hardware->dmi.system.serial;

    dump_options[9].flag = NULL;
    dump_options[9].item = NULL;

    for (int i = 0; i < 9; i++) {
	if (strcmp(option, dump_options[i].flag) == 0) {
	    return remove_spaces(dump_options[i].item);
	}
    }

    return NULL;
}

char *compute_filename(struct s_hardware *hardware)
{

    char *filename = malloc(512);
    snprintf(filename, 512, "%s/%s", hardware->dump_path,
	     hardware->dump_filename);

    /* Until we found some dump parameters */
    char *buffer;
    while ((buffer = strstr(filename, "%{"))) {
	// Find the end of the parameter
	char *buffer_end = strstr(buffer, "}");

	// Extracting the parameter between %{ and }
	char option[8] = { 0 };
	strncpy(option, buffer, buffer_end - buffer + 1);

	/* Replace this option by its value in the filename 
	 * Filename is longer than the previous filename we had
	 * so let's restart from the beginning */
	filename =
	    strreplace(filename, option,
		       get_value_from_option(hardware, option));
    }

    /* We replace the ":" in the filename by some "-"
     * This will avoid Microsoft FS turning crazy */
    chrreplace(filename, ':', '-');

    /* Avoid space to make filename easier to manipulate */
    chrreplace(filename, ' ', '_');

    return filename;
}

int dumpprintf(FILE * p, const char *format, ...)
{
    va_list ap;
    int rv;

    (void)p;
    va_start(ap, format);
    rv = vbufprintf(&p_buf, format, ap);
    va_end(ap);
    return rv;
}

void to_cpio(char *filename)
{
    cpio_writefile(upload, filename, p_buf.buf, p_buf.len);
    if ((p_buf.buf) && (p_buf.len > 0)) {
	memset(p_buf.buf, 0, p_buf.len);
	free(p_buf.buf);
	p_buf.buf = NULL;
	p_buf.size = 0;
	p_buf.len = 0;
    }
}

void flush(ZZJSON_CONFIG * config, ZZJSON ** item)
{
    zzjson_print(config, *item);
    zzjson_free(config, *item);
    *item = NULL;
}

/**
 * dump - dump info
 **/
void dump(struct s_hardware *hardware)
{
    if (hardware->is_pxe_valid == false) {
	more_printf("PXE stack was not detected, Dump feature is not available\n");
	return;
    }

    const union syslinux_derivative_info *sdi = syslinux_derivative_info();
    int err = 0;
    ZZJSON *json = NULL;
    ZZJSON_CONFIG config = { ZZJSON_VERY_STRICT, NULL,
	(int (*)(void *))fgetc,
	NULL,
	malloc, calloc, free, realloc,
	stderr, NULL, stdout,
	(int (*)(void *, const char *,...))dumpprintf,
	(int (*)(int, void *))fputc
    };

    memset(&p_buf, 0, sizeof(p_buf));

    /* By now, we only support TFTP reporting */
    upload = &upload_tftp;
    upload->name = "tftp";

    /* The following defines the behavior of the reporting */
    char *arg[64];
    char *filename = compute_filename(hardware);

    /* The filename */
    arg[0] = filename;
    /* The server to upload the file */
    if (strlen(hardware->tftp_ip) != 0) {
	arg[1] = hardware->tftp_ip;
	arg[2] = NULL;
    } else {
	arg[1] = NULL;
	snprintf(hardware->tftp_ip, sizeof(hardware->tftp_ip),
		 "%u.%u.%u.%u",
		 ((uint8_t *) & sdi->pxe.ipinfo->serverip)[0],
		 ((uint8_t *) & sdi->pxe.ipinfo->serverip)[1],
		 ((uint8_t *) & sdi->pxe.ipinfo->serverip)[2],
		 ((uint8_t *) & sdi->pxe.ipinfo->serverip)[3]);

    }

    /* We initiate the cpio to send */
    cpio_init(upload, (const char **)arg);

    dump_cpu(hardware, &config, &json);
    dump_pxe(hardware, &config, &json);
    dump_syslinux(hardware, &config, &json);
    dump_vpd(hardware, &config, &json);
    dump_vesa(hardware, &config, &json);
    dump_disks(hardware, &config, &json);
    dump_dmi(hardware, &config, &json);
    dump_memory(hardware, &config, &json);
    dump_pci(hardware, &config, &json);
    dump_acpi(hardware, &config, &json);
    dump_kernel(hardware, &config, &json);
    dump_hdt(hardware, &config, &json);

    /* We close & flush the file to send */
    cpio_close(upload);

    if ((err = flush_data(upload)) != TFTP_OK) {
	/* As we manage a tftp connection, let's display the associated error message */
	more_printf("Dump failed !\n");
	more_printf("TFTP ERROR on  : %s:/%s \n", hardware->tftp_ip, filename);
	more_printf("TFTP ERROR msg : %s \n", tftp_string_error_message[-err]);
    } else {
	more_printf("Dump file sent at %s:/%s\n", hardware->tftp_ip, filename);
    }
}
