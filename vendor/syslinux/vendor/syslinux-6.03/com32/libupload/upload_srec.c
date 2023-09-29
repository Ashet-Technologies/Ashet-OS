/*
 * S-records dump routine -- dumps S-records on the console
 */

#include <string.h>
#include <stdio.h>
#include <inttypes.h>
#include <minmax.h>
#include "upload_backend.h"

/* Write a single S-record */
static int write_srecord(unsigned int len,  unsigned int alen,
                         uint32_t addr, uint8_t type, const void *data)
{
    char buf[2+2+8+255*2+2+2];
    char *p = buf;
    uint8_t csum;
    const uint8_t *dptr = data;
    unsigned int i;

    switch (alen) {
    case 2:
        addr &= 0xffff;
        break;
    case 3:
        addr &= 0xffffff;
        break;
    case 4:
        break;
    }

    csum = (len+alen+1) + addr + (addr >> 8) + (addr >> 16) + (addr >> 24);
    for (i = 0; i < len; i++)
        csum += dptr[i];
    csum = 0xff-csum;

    p += sprintf(p, "S%c%02X%0*X", type, len+alen+1, alen*2, addr);
    for (i = 0; i < len; i++)
        p += sprintf(p, "%02X", dptr[i]);
    p += sprintf(p, "%02X\n", csum);

    fputs(buf, stdout);
    return 0;
}

static int upload_srec_write(struct upload_backend *be)
{
    char name[33];
    const char *buf;
    size_t len, chunk, offset, hdrlen;

    buf = be->outbuf;
    len = be->zbytes;

    putchar('\n');

    hdrlen = snprintf(name, sizeof name, "%.32s",
		      be->argv[0] ? be->argv[0] : "");

    /* Write head record */
    write_srecord(hdrlen, 2, 0, '0', name);

    /* Write data records */
    offset = 0;
    while (len) {
	chunk = min(len, (size_t)32);

	write_srecord(chunk, 4, offset, '3', buf);
	buf += chunk;
	len -= chunk;
	offset += chunk;
    }

    /* Write termination record */
    write_srecord(0, 4, 0, '7', NULL);

    return 0;
}

struct upload_backend upload_srec = {
    .name       = "srec",
    .helpmsg    = "[filename]",
    .minargs    = 0,
    .write      = upload_srec_write,
};
