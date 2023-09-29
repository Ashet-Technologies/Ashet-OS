/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2010 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * Dump ACPI information
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "sysdump.h"
#include "rbtree.h"

struct acpi_rsdp {
    uint8_t  magic[8];		/* "RSD PTR " */
    uint8_t  csum;
    char     oemid[6];
    uint8_t  rev;
    uint32_t rsdt_addr;
    uint32_t len;
    uint64_t xsdt_addr;
    uint8_t  xcsum;
    uint8_t  rsvd[3];
};

struct acpi_hdr {
    char     sig[4];		/* Signature */
    uint32_t len;
    uint8_t  rev;
    uint8_t  csum;
    char     oemid[6];
    char     oemtblid[16];
    uint32_t oemrev;
    uint32_t creatorid;
    uint32_t creatorrev;
};

struct acpi_rsdt {
    struct acpi_hdr hdr;
    uint32_t entry[0];
};

struct acpi_xsdt {
    struct acpi_hdr hdr;
    uint64_t entry[0];
};

static struct rbtree *rb_types, *rb_addrs;

static bool rb_has(struct rbtree **tree, uint64_t key)
{
    struct rbtree *node;

    node = rb_search(*tree, key);
    if (node && node->key == key)
	return true;

    node = malloc(sizeof *node);
    if (node) {
	node->key = key;
	*tree = rb_insert(*tree, node);
    }
    return false;
}

static inline bool addr_ok(uint64_t addr)
{
    /* We can only handle 32-bit addresses for now... */
    return addr <= 0xffffffff;
}

enum tbl_errs {
    ERR_NONE,			/* No errors */
    ERR_CSUM,			/* Invalid checksum */
    ERR_SIZE,			/* Impossibly large table */
    ERR_NOSIG			/* No signature */
};

static uint8_t checksum_range(const void *start, uint32_t size)
{
    const uint8_t *p = start;
    uint8_t csum = 0;

    while (size--)
	csum += *p++;

    return csum;
}

static enum tbl_errs is_valid_table(const void *ptr)
{
    const struct acpi_hdr *hdr = ptr;

    if (hdr->sig[0] == 0)
	return ERR_NOSIG;

    if (hdr->len < 10 || hdr->len > (1 << 20)) {
	/* Either insane or too large to dump */
	return ERR_SIZE;
    }

    return checksum_range(hdr, hdr->len) == 0 ? ERR_NONE : ERR_CSUM;
}

static const struct acpi_rsdp *scan_for_rsdp(uint32_t base, uint32_t end)
{
    for (base &= ~15; base < end-20; base += 16) {
	const struct acpi_rsdp *rsdp = (const struct acpi_rsdp *)base;

	if (memcmp(rsdp->magic, "RSD PTR ", 8))
	    continue;

	if (checksum_range(rsdp, 20))
	    continue;

	if (rsdp->rev > 0) {
	    if (base + rsdp->len >= end ||
		checksum_range(rsdp, rsdp->len))
		continue;
	}

	return rsdp;
    }

    return NULL;
}

static const struct acpi_rsdp *find_rsdp(void)
{
    uint32_t ebda;
    const struct acpi_rsdp *rsdp;

    ebda = (*(uint16_t *)0x40e) << 4;
    if (ebda >= 0x70000 && ebda < 0xa0000) {
	rsdp = scan_for_rsdp(ebda, ebda+1024);

	if (rsdp)
	    return rsdp;
    }

    return scan_for_rsdp(0xe0000, 0x100000);
}

static void dump_table(struct upload_backend *be,
		       const char name[], const void *ptr, uint32_t len)
{
    char namebuf[64];
    uint32_t name_key = *(uint32_t *)name;

    if (rb_has(&rb_addrs, (size_t)ptr))
	return;			/* Already dumped this table */

    if (!rb_has(&rb_types, name_key)) {
	snprintf(namebuf, sizeof namebuf, "acpi/%4.4s", name);
	cpio_mkdir(be, namebuf);
    }

    snprintf(namebuf, sizeof namebuf, "acpi/%4.4s/%08x", name, (uint32_t)ptr);
    cpio_hdr(be, MODE_FILE, len, namebuf);

    write_data(be, ptr, len);
}

static void dump_rsdt(struct upload_backend *be, const struct acpi_rsdp *rsdp)
{
    const struct acpi_rsdt *rsdt;
    uint32_t i, n;

    rsdt = (const struct acpi_rsdt *)rsdp->rsdt_addr;

    if (memcmp(rsdt->hdr.sig, "RSDT", 4) || is_valid_table(rsdt) > ERR_CSUM)
	return;

    dump_table(be, rsdt->hdr.sig, rsdt, rsdt->hdr.len);

    if (rsdt->hdr.len < 36)
	return;

    n = (rsdt->hdr.len - 36) >> 2;

    for (i = 0; i < n; i++) {
	const struct acpi_hdr *hdr = (const struct acpi_hdr *)(rsdt->entry[i]);

	if (is_valid_table(hdr) <= ERR_CSUM)
	    dump_table(be, hdr->sig, hdr, hdr->len);
    }
}

static void dump_xsdt(struct upload_backend *be, const struct acpi_rsdp *rsdp)
{
    const struct acpi_xsdt *xsdt;
    uint32_t rsdp_len = rsdp->rev > 0 ? rsdp->len : 20;
    uint32_t i, n;

    if (rsdp_len < 34)
	return;

    if (!addr_ok(rsdp->xsdt_addr))
	return;

    xsdt = (const struct acpi_xsdt *)(size_t)rsdp->xsdt_addr;

    if (memcmp(xsdt->hdr.sig, "XSDT", 4) || is_valid_table(xsdt) > ERR_CSUM)
	return;

    dump_table(be, xsdt->hdr.sig, xsdt, xsdt->hdr.len);

    if (xsdt->hdr.len < 36)
	return;

    n = (xsdt->hdr.len - 36) >> 3;

    for (i = 0; i < n; i++) {
	const struct acpi_hdr *hdr;
	if (addr_ok(xsdt->entry[i])) {
	    hdr = (const struct acpi_hdr *)(size_t)(xsdt->entry[i]);

	    if (is_valid_table(hdr) <= ERR_CSUM)
		dump_table(be, hdr->sig, hdr, hdr->len);
	}
    }
}

void dump_acpi(struct upload_backend *be)
{
    const struct acpi_rsdp *rsdp;
    uint32_t rsdp_len;

    rsdp = find_rsdp();

    printf("Dumping ACPI... ");

    if (!rsdp)
	return;			/* No ACPI information found */

    cpio_mkdir(be, "acpi");

    rsdp_len = rsdp->rev > 0 ? rsdp->len : 20;

    dump_table(be, "RSDP", rsdp, rsdp_len);

    dump_rsdt(be, rsdp);
    dump_xsdt(be, rsdp);

    rb_destroy(rb_types);
    rb_destroy(rb_addrs);

    printf("done.\n");
}
