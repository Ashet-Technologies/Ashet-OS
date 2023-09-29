/*
 * Dump DMI information in a way hopefully compatible with dmidecode
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "sysdump.h"

struct dmi_header {
    char signature[5];
    uint8_t csum;
    uint16_t tbllen;
    uint32_t tbladdr;
    uint16_t nstruc;
    uint8_t revision;
    uint8_t reserved;
};

struct smbios_header {
    char signature[4];
    uint8_t csum;
    uint8_t len;
    uint8_t major;
    uint8_t minor;
    uint16_t maxsize;
    uint8_t revision;
    uint8_t fmt[5];

    struct dmi_header dmi;
};

static uint8_t checksum(const void *buf, size_t len)
{
    const uint8_t *p = buf;
    uint8_t csum = 0;

    while (len--)
	csum += *p++;

    return csum;
}

static bool is_old_dmi(size_t dptr)
{
    const struct dmi_header *dmi = (void *)dptr;

    return !memcmp(dmi->signature, "_DMI_", 5) &&
	!checksum(dmi, 0x0f);
    return false;
}

static bool is_smbios(size_t dptr)
{
    const struct smbios_header *smb = (void *)dptr;

    return !memcmp(smb->signature, "_SM_", 4) &&
	!checksum(smb, smb->len) &&
	is_old_dmi(dptr+16);
}

static void dump_smbios(struct upload_backend *be, size_t dptr)
{
    const struct smbios_header *smb = (void *)dptr;
    struct smbios_header smx = *smb;
    char filename[32];

    snprintf(filename, sizeof filename, "dmi/%05x.%08x",
	     dptr, smb->dmi.tbladdr);
    cpio_hdr(be, MODE_FILE, smb->dmi.tbllen + 32, filename);

    /*
     * Adjust the address of the smbios table to be 32, to
     * make dmidecode happy.  The checksum on the smbios table is unchanged,
     * since it includes the checksum on the dmi table.
     */
    smx.dmi.tbladdr = sizeof smx;
    smx.dmi.csum -= checksum(&smx.dmi, 0x0f);

    write_data(be, &smx, sizeof smx);
    write_data(be, (const void *)smb->dmi.tbladdr, smb->dmi.tbllen);
}

static void dump_old_dmi(struct upload_backend *be, size_t dptr)
{
    const struct dmi_header *dmi = (void *)dptr;
    struct fake {
	struct dmi_header dmi;
	char pad[16];
    } fake;
    char filename[32];

    snprintf(filename, sizeof filename, "dmi/%05x.%08x",
	     dptr, dmi->tbladdr);
    cpio_hdr(be, MODE_FILE, dmi->tbllen + 32, filename);

    /*
     * Adjust the address of the smbios table to be 32, to
     * make dmidecode happy.
     */
    fake.dmi = *dmi;
    memset(&fake.pad, 0, sizeof fake.pad);
    fake.dmi.tbladdr = sizeof fake;
    fake.dmi.csum -= checksum(&fake.dmi, 0x0f);

    write_data(be, &fake, sizeof fake);
    write_data(be, (const void *)dmi->tbladdr, dmi->tbllen);
}

void dump_dmi(struct upload_backend *be)
{
    size_t dptr;

    cpio_mkdir(be, "dmi");

    /* Search for _SM_ or _DMI_ structure */
    for (dptr = 0xf0000 ; dptr < 0x100000 ; dptr += 16) {
	if (is_smbios(dptr)) {
	    dump_smbios(be, dptr);
	    dptr += 16;		/* Skip the subsequent DMI header */
	} else if (is_old_dmi(dptr)) {
	    dump_old_dmi(be, dptr);
	}
    }
}
