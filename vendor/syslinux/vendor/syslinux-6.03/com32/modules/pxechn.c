/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2010-2012 Gene Cumm - All Rights Reserved
 *
 *   Portions from chain.c:
 *   Copyright 2003-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
 *   Significant portions copyright (C) 2010 Shao Miller
 *					[partition iteration, GPT, "fs"]
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * pxechn.c
 *
 * PXE Chain Loader; Chain load to another PXE network boot program
 * that may be on another host.
 */

#include <stdio.h>
#include <stdlib.h>
#include <consoles.h>
#include <console.h>
#include <errno.h>
#include <string.h>
#include <syslinux/config.h>
#include <syslinux/loadfile.h>
#include <syslinux/bootrm.h>
#include <syslinux/video.h>
#include <com32.h>
#include <stdint.h>
#include <syslinux/pxe.h>
#include <sys/gpxe.h>
#include <unistd.h>
#include <getkey.h>
#include <dhcp.h>
#include <limits.h>


#ifdef DEBUG
#  define PXECHN_DEBUG 1
#else
#  define PXECHN_DEBUG 0
#endif

typedef union {
    uint64_t q;
    uint32_t l[2];
    uint16_t w[4];
    uint8_t b[8];
} reg64_t;

#define dprintf0(f, ...)		((void)0)

#ifndef dprintf
#  if (PXECHN_DEBUG > 0)
#    define dprintf			printf
#  else
#    define dprintf(f, ...)		((void)0)
#  endif
#endif

#if (PXECHN_DEBUG > 0)
#  define dpressanykey			pressanykey
#  define dprint_pxe_bootp_t		print_pxe_bootp_t
#  define dprint_pxe_vendor_blk		print_pxe_vendor_blk
#  define dprint_pxe_vendor_raw		print_pxe_vendor_raw
#else
#  define dpressanykey(tm)		((void)0)
#  define dprint_pxe_bootp_t(p, l)	((void)0)
#  define dprint_pxe_vendor_blk(p, l)	((void)0)
#  define dprint_pxe_vendor_raw(p, l)	((void)0)
#endif

#define dprintf_opt_cp		dprintf0
#define dprintf_opt_inj		dprintf0
#define dprintf_pc_pa		dprintf
#define dprintf_pc_so_s		dprintf0

#define t_PXENV_RESTART_TFTP	t_PXENV_TFTP_READ_FILE

#define STACK_SPLIT	11

/* same as pxelinux.asm REBOOT_TIME */
#define REBOOT_TIME	300

#define NUM_DHCP_OPTS		256
#define DHCP_OPT_LEN_MAX	256
#define PXE_VENDOR_RAW_PRN_MAX	0x7F
#define PXECHN_HOST_LEN		256	/* 63 bytes per label; 255 max total */

#define PXECHN_NUM_PKT_TYPE	3
#define PXECHN_NUM_PKT_AVAIL	2*PXECHN_NUM_PKT_TYPE
#define PXECHN_PKT_TYPE_START	PXENV_PACKET_TYPE_DHCP_DISCOVER

#define PXECHN_FORCE_PKT1	0x80000000
#define PXECHN_FORCE_PKT2	0x40000000
#define PXECHN_FORCE_ALL	(PXECHN_FORCE_PKT1 | PXECHN_FORCE_PKT2)
#define PXECHN_FORCE_ALL_1	0
#define STRASINT_str		('s' + (('t' + ('r' << 8)) << 8))

#define min(a,b) (((a) < (b)) ? (a) : (b))

const char app_name_str[] = "pxechn.c32";

struct pxelinux_opt {
    char *fn;	/* Filename as passed to us */
    in_addr_t fip;	/* fn's IP component */
    char *fp;	/* fn's path component */
    in_addr_t gip;	/* giaddr; Gateway/DHCP relay */
    uint32_t force;
    uint32_t wait;	/* Additional decision to wait before boot */
    int32_t wds;	/* WDS option/level */
    in_addr_t sip;	/* siaddr: Next Server IP Address */
    struct dhcp_option p[PXECHN_NUM_PKT_AVAIL];
	/* original _DHCP_DISCOVER, _DHCP_ACK, _CACHED_REPLY then modified packets */
    char host[PXECHN_HOST_LEN];
    struct dhcp_option opts[PXECHN_NUM_PKT_TYPE][NUM_DHCP_OPTS];
    char p_unpacked[PXECHN_NUM_PKT_TYPE];
};


/* from chain.c */
struct data_area {
    void *data;
    addr_t base;
    addr_t size;
};

/* From chain.c */
static inline void error(const char *msg)
{
    fputs(msg, stderr);
}

/* From chain.c */
static void do_boot(struct data_area *data, int ndata,
		    struct syslinux_rm_regs *regs)
{
    uint16_t *const bios_fbm = (uint16_t *) 0x413;
    addr_t dosmem = *bios_fbm << 10;	/* Technically a low bound */
    struct syslinux_memmap *mmap;
    struct syslinux_movelist *mlist = NULL;
    addr_t endimage;
    int i;

    mmap = syslinux_memory_map();

    if (!mmap) {
	error("Cannot read system memory map\n");
	return;
    }

    endimage = 0;
    for (i = 0; i < ndata; i++) {
	if (data[i].base + data[i].size > endimage)
	    endimage = data[i].base + data[i].size;
    }
    if (endimage > dosmem)
	goto too_big;

    for (i = 0; i < ndata; i++) {
	if (syslinux_add_movelist(&mlist, data[i].base,
				  (addr_t) data[i].data, data[i].size))
	    goto enomem;
    }


    /* Tell the shuffler not to muck with this area... */
    syslinux_add_memmap(&mmap, endimage, 0xa0000 - endimage, SMT_RESERVED);

    /* Force text mode */
    syslinux_force_text_mode();

    fputs("Booting...\n", stdout);
    syslinux_shuffle_boot_rm(mlist, mmap, 3, regs);
    error("Chainboot failed!\n");
    return;

too_big:
    error("Loader file too large\n");
    return;

enomem:
    error("Out of memory\n");
    return;
}

void usage(void)
{
    printf("USAGE:\n"
        "    %s [OPTIONS]... _new-nbp_\n"
	"    %s -r _new-nbp_    (calls PXE stack PXENV_RESTART_TFTP)\n"
	"OPTIONS:\n"
	"    [-c config] [-g gateway] [-p prefix] [-t reboot] [-u] [-w] [-W]"
	" [-o opt.ty=val]\n\n",
	app_name_str, app_name_str);
}

void pxe_error(int ierr, const char *evt, const char *msg)
{
    if (msg)
	printf("%s", msg);
    else if (evt)
	printf("Error while %s: ", evt);
    printf("%d:%s\n", ierr, strerror(ierr));
}

int pressanykey(clock_t tm) {
    int inc;

    printf("Press any key to continue. ");
    inc = get_key(stdin, tm);
    puts("");
    return inc;
}

int dhcp_find_opt(pxe_bootp_t *p, size_t len, uint8_t opt)
{
    int rv = -1;
    int i, vlen, oplen;
    uint8_t *d;
    uint32_t magic;

    if (!p) {
	dprintf("  packet pointer is null\n");
	return rv;
    }
    vlen = len - ((void *)&(p->vendor) - (void *)p);
    d = p->vendor.d;
    magic = ntohl(*((uint32_t *)d));
    if (magic != VM_RFC1048)	/* Invalid DHCP packet */
	vlen = 0;
    for (i = 4; i < vlen; i++) {
	if (d[i] == opt) {
	    dprintf("\n    @%03X-%2d\n", i, d[i]);
	    rv = i;
	    break;
	}
	if (d[i] == ((NUM_DHCP_OPTS) - 1))	/* End of list */
	    break;
	if (d[i]) {		/* Skip padding */
	    oplen = d[++i];
	    i += oplen;
	}
    }
    return rv;
}

void print_pxe_vendor_raw(pxe_bootp_t *p, size_t len)
{
    int i, vlen;

    if (!p) {
	printf("  packet pointer is null\n");
	return;
    }
    vlen = len - ((void *)&(p->vendor) - (void *)p);
    if (vlen > PXE_VENDOR_RAW_PRN_MAX)
	vlen = PXE_VENDOR_RAW_PRN_MAX;
    dprintf("  rawLen = %d", vlen);
    for (i = 0; i < vlen; i++) {
	if ((i & 0xf) == 0)
	    printf("\n  %04X:", i);
	printf(" %02X", p->vendor.d[i]);
    }
    printf("\n");
}

void print_pxe_vendor_blk(pxe_bootp_t *p, size_t len)
{
    int i, vlen, oplen, j;
    uint8_t *d;
    uint32_t magic;
    if (!p) {
	printf("  packet pointer is null\n");
	return;
    }
    vlen = len - ((void *)&(p->vendor) - (void *)p);
    printf("  Vendor Data:    Len=%d", vlen);
    d = p->vendor.d;
    magic = ntohl(*((uint32_t *)d));
    printf("    Magic: %08X", ntohl(*((uint32_t *)d)));
    if (magic != VM_RFC1048)	/* Invalid DHCP packet */
	vlen = 0;
    for (i = 4; i < vlen; i++) {
	if (d[i])	/* Skip the padding */
	    printf("\n    @%03X-%3d", i, d[i]);
	if (d[i] == ((NUM_DHCP_OPTS) - 1))	/* End of list */
	    break;
	if (d[i]) {
	    oplen = d[++i];
	    printf(" l=%3d:", oplen);
	    for (j = (++i + oplen); i < vlen && i < j; i++) {
		printf(" %02X", d[i]);
	    }
	    i--;
	}
    }
    printf("\n");
}

void print_pxe_bootp_t(pxe_bootp_t *p, size_t len)
{
    if (!p || len <= 0) {
	printf("  packet pointer is null\n");
	return;
    }
    printf("  op:%02X  hw:%02X  hl:%02X  gh:%02X  id:%08X se:%04X f:%04X"
	"  cip:%08X\n", p->opcode, p->Hardware, p->Hardlen, p->Gatehops,
	ntohl(p->ident), ntohs(p->seconds), ntohs(p->Flags), ntohl(p->cip));
    printf("  yip:%08X  sip:%08X  gip:%08X",
	ntohl(p->yip), ntohl(p->sip), ntohl(p->gip));
    printf("  caddr-%02X:%02X:%02X:%02X:%02X:%02X\n", p->CAddr[0],
	p->CAddr[1], p->CAddr[2], p->CAddr[3], p->CAddr[4], p->CAddr[5]);
    printf("  sName: '%s'\n", p->Sname);
    printf("  bootfile: '%s'\n", p->bootfile);
    dprint_pxe_vendor_blk(p, len);
}

void pxe_set_regs(struct syslinux_rm_regs *regs)
{
    const union syslinux_derivative_info *sdi;
    const com32sys_t *pxe_regs;

    sdi = syslinux_derivative_info();
    pxe_regs = sdi->pxe.stack;	/* Original register values */

    /* Just to be sure... */
    memset(regs, 0, sizeof *regs);

    regs->ip = 0x7C00;

    /* Point to the original stack */
    regs->ss    = sdi->pxe.stack_seg;
    regs->esp.l = sdi->pxe.stack_offs + sizeof(com32sys_t);

    /* Point to the PXENV+ address */
    regs->es    = pxe_regs->es;
    regs->ebx.l = pxe_regs->ebx.l;

    dprintf("\nsp:%04x    ss:%04x    es:%04x    bx:%04x\n", regs->esp.w[0],
	regs->ss, regs->es, regs->ebx.w[0]);
}

int hostlen_limit(int len)
{
    return min(len, ((PXECHN_HOST_LEN) - 1));
}

//FIXME: To a library
/* Parse a filename into an IPv4 address and filename pointer
 *	returns	Based on the interpretation of fn
 *		0 regular file name
 *		1 in format IP::FN
 *		2 TFTP URL
 *		3 HTTP URL
 *		4 FTP URL
 *		3 + 2^30 HTTPS URL
 *		-1 if fn is another URL type
 */
int pxechn_parse_fn(char fn[], in_addr_t *fip, char *host, char *fp[])
{
    in_addr_t tip = 0;
    char *csep, *ssep, *hsep;	/* Colon, Slash separator positions */
    int hlen, plen;	/* Hostname, protocol length */
    int rv = 0;

    csep = strchr(fn, ':');
    if (csep) {
	if (csep[1] == ':') {	/* assume IP::FN */
	    *fp = &csep[2];
	    rv = 1;
	    if (fn[0] != ':') {
		hlen = hostlen_limit(csep - fn);
		memcpy(host, fn, hlen);
		host[hlen] = 0;
	    }
	} else if ((csep[1] == '/') && (csep[2] == '/')) {
		/* URL: proto://host:port/path/file */
		/* proto://[user[:passwd]@]host[:port]/path/file */
	    ssep = strchr(csep + 3, '/');
	    if (ssep) {
		hlen = hostlen_limit(ssep - (csep + 3));
		*fp = ssep + 1;
	    } else {
		hlen = hostlen_limit(strlen(csep + 3));
	    }
	    memcpy(host, (csep + 3), hlen);
	    host[hlen] = 0;
	    plen = csep - fn;
	    if (strncmp(fn, "tftp", plen) == 0)
		rv = 2;
	    else if (strncmp(fn, "http", plen) == 0)
		rv = 3;
	    else if (strncmp(fn, "ftp", plen) == 0)
		rv = 4;
	    else if (strncmp(fn, "https", plen) == 0)
		rv = 3 + ( 1 << 30 );
	    else
		rv = -1;
	} else {
	    csep = NULL;
	}
    }
    if (!csep) {
	*fp = fn;
    }
    if (host[0]) {
	hsep = strchr(host, '@');
	if (!hsep)
	    hsep = host;
	tip = pxe_dns(hsep);
    }
    if (tip != 0)
	*fip = tip;
    dprintf0("  host '%s'\n  fp   '%s'\n  fip  %08x\n", host, *fp, ntohl(*fip));
    return rv;
}

void pxechn_opt_free(struct dhcp_option *opt)
{
    free(opt->data);
    opt->len = -1;
}

void pxechn_fill_pkt(struct pxelinux_opt *pxe, int ptype)
{
    int rv = -1;
    int p1, p2;
    if ((ptype < 0) || (ptype > PXECHN_NUM_PKT_TYPE))
	rv = -2;
    p1 = ptype - PXECHN_PKT_TYPE_START;
    p2 = p1 + PXECHN_NUM_PKT_TYPE;
    if ((rv >= -1) && (!pxe_get_cached_info(ptype,
	    (void **)&(pxe->p[p1].data), (size_t *)&(pxe->p[p1].len)))) {
	pxe->p[p2].data = malloc(2048);
	if (pxe->p[p2].data) {
	    memcpy(pxe->p[p2].data, pxe->p[p1].data, pxe->p[p1].len);
	    pxe->p[p2].len = pxe->p[p1].len;
	    rv = 0;
	    dprint_pxe_bootp_t((pxe_bootp_t *)(pxe->p[p1].data), pxe->p[p1].len);
	    dpressanykey(INT_MAX);
	} else {
	    printf("%s: ERROR: Unable to malloc() for second packet\n", app_name_str);
	}
    } else {
	printf("%s: ERROR: Unable to retrieve first packet\n", app_name_str);
    }
    if (rv <= -1) {
	pxechn_opt_free(&pxe->p[p1]);
    }
}

void pxechn_init(struct pxelinux_opt *pxe)
{
    /* Init for paranoia */
    pxe->fn = NULL;
    pxe->fp = NULL;
    pxe->force = 0;
    pxe->wait = 0;
    pxe->gip = 0;
    pxe->wds = 0;
    pxe->sip = 0;
    pxe->host[0] = 0;
    pxe->host[((NUM_DHCP_OPTS) - 1)] = 0;
    for (int j = 0; j < PXECHN_NUM_PKT_TYPE; j++){
	for (int i = 0; i < NUM_DHCP_OPTS; i++) {
	    pxe->opts[j][i].data = NULL;
	    pxe->opts[j][i].len = -1;
	}
	pxe->p_unpacked[j] = 0;
	pxe->p[j].data = NULL;
	pxe->p[j+PXECHN_NUM_PKT_TYPE].data = NULL;
	pxe->p[j].len = 0;
	pxe->p[j+PXECHN_NUM_PKT_TYPE].len = 0;
    }
    pxechn_fill_pkt(pxe, PXENV_PACKET_TYPE_CACHED_REPLY);
}

int pxechn_to_hex(char i)
{
    if (i >= '0' && i <= '9')
	return (i - '0');
    if (i >= 'A' && i <= 'F')
	return (i - 'A' + 10);
    if (i >= 'a' && i <= 'f')
	return (i - 'a' + 10);
    if (i == 0)
	return -1;
    return -2;
}

int pxechn_parse_2bhex(char ins[])
{
    int ret = -2;
    int n0 = -3, n1 = -3;
    /* NULL pointer */
    if (!ins) {
	ret = -1;
    /* pxechn_to_hex can handle the NULL character by returning -1 and
       breaking the execution of the statement chain */
    } else if (((n0 = pxechn_to_hex(ins[0])) >= 0)
	    && ((n1 = pxechn_to_hex(ins[1])) >= 0)) {
	ret = (n0 * 16) + n1;
    } else if (n0 == -1) {	/* Leading NULL char */
	ret = -1;
    }
    return ret;
}

int pxechn_optnum_ok(int optnum)
{
    if ((optnum > 0) && (optnum < ((NUM_DHCP_OPTS) - 1)))
	return 1;
    return 0;
}

int pxechn_optnum_ok_notres(int optnum)
{
    if ((optnum <= 0) && (optnum >= ((NUM_DHCP_OPTS) - 1)))
	return 0;
    switch(optnum){
    case 66: case 67:
	return 0;
	break;
    default:	return 1;
    }
}

int pxechn_optlen_ok(int optlen)
{
    if ((optlen >= 0) && (optlen < ((DHCP_OPT_LEN_MAX) - 1)))
	return 1;
    return 0;
}

int pxechn_setopt(struct dhcp_option *opt, void *data, int len)
{
    void *p;
    if (!opt || !data)
	return -1;
    if (len < 0) {
	return -3;
    }
    p = realloc(opt->data, len);
    if (!p && len) {	/* Allow for len=0 */
	pxechn_opt_free(opt);
	return -2;
    }
    opt->data = p;
    memcpy(opt->data, data, len);
    opt->len = len;
    return len;
}

int pxechn_setopt_str(struct dhcp_option *opt, void *data)
{
    return pxechn_setopt(opt, data, strnlen(data, DHCP_OPT_LEN_MAX));
}

int pxechn_parse_int(char *data, char istr[], int tlen)
{
    int terr = errno;

    if ((tlen == 1) || (tlen == 2) || (tlen == 4)) {
	errno = 0;
	uint32_t optval = strtoul(istr, NULL, 0);
	if (errno)
	    return -3;
	errno = terr;
	switch(tlen){
	case  1:
	    if (optval & 0xFFFFFF00)
		return -4;
	    break;
	case  2:
	    if (optval & 0xFFFF0000)
		return -4;
	    optval = htons(optval);
	    break;
	case  4:
	    optval = htonl(optval);
	    break;
	}
	memcpy(data, &optval, tlen);
    } else if (tlen == 8) {
	errno = 0;
	uint64_t optval = strtoull(istr, NULL, 0);
	if (errno)
	    return -3;
	errno = terr;
	optval = htonq(optval);
	memcpy(data, &optval, tlen);
    } else {
	return -2;
    }
    return tlen;
}

int pxechn_parse_hex_sep(char *data, char istr[], char sep)
{
    int len = 0;
    int ipos = 0, ichar;
    
    if (!data || !istr)
	return -1;
    while ((istr[ipos]) && (len < DHCP_OPT_LEN_MAX)) {
	dprintf(" %02X%02X", *((int *)(istr + ipos)) & 0xFF, *((int *)(istr + ipos +1)) & 0xFF);
	ichar = pxechn_parse_2bhex(istr + ipos);
	if (ichar >=0) {
	    data[len++] = ichar;
	} else {
	    return -EINVAL;
	}
	if (!istr[ipos+2]){
	    ipos += 2;
	} else if (istr[ipos+2] != sep) {
	    return -(EINVAL + 1);
	} else {
	    ipos += 3;
	}
    }
    return len;
}

int pxechn_parse_opttype(char istr[], int optnum)
{
    char *pos;
    int tlen, type, tmask;

    if (!istr)
	return -1;
    pos = strchr(istr, '=');
    if (!pos)
	return -2;
    if (istr[0] != '.') {
	if (!pxechn_optnum_ok(optnum))
	    return -3;
	return -3;	/* do lookup here */
    } else {
	tlen = pos - istr - 1;
	if ((tlen < 1) || (tlen > 4))
	    return -4;
	tmask = 0xFFFFFFFF >> (8 * (4 - tlen));
	type = (*(int*)(istr + 1)) & tmask;
    }
    return type;
}

int pxechn_parse_setopt(struct dhcp_option opts[], struct dhcp_option *iopt,
			char istr[])
{
    int rv = 0, optnum, opttype;
    char *cpos = NULL, *pos;

    if (!opts || !iopt || !(iopt->data))
	return -1;
    if (!istr || !istr[0])
	return -2;
    // -EINVAL;
    optnum = strtoul(istr, &cpos, 0);
    if (!pxechn_optnum_ok(optnum))
	return -3;
    pos = strchr(cpos, '=');
    if (!pos)
	return -4;
    opttype = pxechn_parse_opttype(cpos, optnum);
    pos++;
    switch(opttype) {
    case 'b':
	iopt->len = pxechn_parse_int(iopt->data, pos, 1);
	break;
    case 'l':
	iopt->len = pxechn_parse_int(iopt->data, pos, 4);
	break;
    case 'q':
	iopt->len = pxechn_parse_int(iopt->data, pos, 8);
	break;
    case 's':
    case STRASINT_str:
	iopt->len = strlen(pos);
	if (iopt->len > DHCP_OPT_LEN_MAX)
	    iopt->len = DHCP_OPT_LEN_MAX;
	memcpy(iopt->data, pos, iopt->len);
	dprintf_pc_so_s("s.len=%d\trv=%d\n", iopt->len, rv);
	break;
    case 'w':
	iopt->len = pxechn_parse_int(iopt->data, pos, 2);
	break;
    case 'x':
	iopt->len = pxechn_parse_hex_sep(iopt->data, pos, ':');
	break;
    default:
	return -6;
	break;
    }
    if (pxechn_optlen_ok(iopt->len)) {
	rv = pxechn_setopt(&(opts[optnum]), (void *)(iopt->data), iopt->len);
    }
    if((opttype == 's') || (opttype == STRASINT_str))
	dprintf_pc_so_s("rv=%d\n", rv);
    return rv;
}

int pxechn_parse_force(const char istr[])
{
    uint32_t rv = 0;
    char *pos;
    int terr = errno;

    errno = 0;
    rv = strtoul(istr, &pos, 0);
    if ((istr == pos ) || ((rv == ULONG_MAX) && (errno)))
	rv = 0;
    errno = terr;
    return rv;
}

int pxechn_uuid_set(struct pxelinux_opt *pxe)
{
    int ret = 0;

    if (!pxe->p_unpacked[0])
	ret = dhcp_unpack_packet((pxe_bootp_t *)(pxe->p[0].data),
				 pxe->p[0].len, pxe->opts[0]);
    if (ret) {
	error("Could not unpack packet\n");
	return -ret;	/* dhcp_unpack_packet always returns positive errors */
    }

    if (pxe->opts[0][97].len >= 0 )
	pxechn_setopt(&(pxe->opts[2][97]), pxe->opts[0][97].data, pxe->opts[0][97].len);
	return 1;
    return 0;
}

int pxechn_parse_args(int argc, char *argv[], struct pxelinux_opt *pxe,
			 struct dhcp_option opts[])
{
    int arg, optnum, rv = 0;
    char *p = NULL;
    const char optstr[] = "c:f:g:o:p:St:uwW";
    struct dhcp_option iopt;

    if (pxe->p[5].data)
	pxe->fip = ( (pxe_bootp_t *)(pxe->p[5].data) )->sip;
    else
	pxe->fip = 0;
    /* Fill */
    pxe->fn = argv[0];
    pxechn_parse_fn(pxe->fn, &(pxe->fip), pxe->host, &(pxe->fp));
    pxechn_setopt_str(&(opts[67]), pxe->fp);
    pxechn_setopt_str(&(opts[66]), pxe->host);
    iopt.data = malloc(DHCP_OPT_LEN_MAX);
    iopt.len = 0;
    while ((rv >= 0) && (arg = getopt(argc, argv, optstr)) >= 0) {
	dprintf_pc_pa("  Got arg '%c'/'%c' addr %08X val %s\n", arg == '?' ? optopt : arg, arg, (unsigned int)optarg, optarg ? optarg : "");
	switch(arg) {
	case 'c':	/* config */
	    pxechn_setopt_str(&(opts[209]), optarg);
	    break;
	case 'f':	/* force */
	    pxe->force = pxechn_parse_force(optarg);
	    break;
	case 'g':	/* gateway/DHCP relay */
	    pxe->gip = pxe_dns(optarg);
	    break;
	case 'n':	/* native */
	    break;
	case 'o':	/* option */
	    rv = pxechn_parse_setopt(opts, &iopt, optarg);
	    break;
	case 'p':	/* prefix */
	    pxechn_setopt_str(&(opts[210]), optarg);
	    break;
	case 'S':	/* sip from sName */
	    pxe->sip = 1;
	    break;
	case 't':	/* timeout */
	    optnum = strtoul(optarg, &p, 0);
	    if (p != optarg) {
		optnum = htonl(optnum);
		pxechn_setopt(&(opts[211]), (void *)(&optnum), 4);
	    } else {
		rv = -3;
	    }
	    break;
	case 'u':	/* UUID: copy option 97 from packet 1 if present */
	    pxechn_uuid_set(pxe);
	    break;
	case 'w':	/* wait */
	    pxe->wait = 1;
	    break;
	case 'W':	/* WDS */
	    pxe->wds = 1;
	    break;
	case '?':
	    rv = -'?';
	default:
	    break;
	}
	if (rv >= 0)	/* Clear it since getopt() doesn't guarentee it */
	    optarg = NULL;
    }
    if (iopt.data)
	pxechn_opt_free(&iopt);
/* FIXME: consider reordering the application of parsed command line options
       such that the new nbp may be at the end */
    if (rv >= 0) {
	rv = 0;
    } else if (arg != '?') {
	printf("Invalid argument for -%c: %s\n", arg, optarg);
    }
    dprintf("pxechn_parse_args rv=%d\n", rv);
    return rv;
}

int pxechn_args(int argc, char *argv[], struct pxelinux_opt *pxe)
{
    pxe_bootp_t *bootp0, *bootp1;
    int ret = 0;
    struct dhcp_option *opts;
    char *str;

    opts = pxe->opts[2];
    /* Start filling packet #1 */
    bootp0 = (pxe_bootp_t *)(pxe->p[2].data);
    bootp1 = (pxe_bootp_t *)(pxe->p[5].data);

    ret = dhcp_unpack_packet(bootp0, pxe->p[2].len, opts);
    if (ret) {
	error("Could not unpack packet\n");
	return -ret;
    }
    pxe->p_unpacked[2] = 1;
    pxe->gip = bootp1->gip;

    ret = pxechn_parse_args(argc, argv, pxe, opts);
    if (ret)
	return ret;
    if (pxe->sip > 0xFFFFFF) {	/* a real IPv4 address */
	bootp1->sip = pxe->sip;
    } else if ((pxe->sip == 1)
		&& (opts[66].len > 0)){
	/* unterminated? */
	if (strnlen(opts[66].data, opts[66].len) == (size_t)opts[66].len) {
	    str = malloc(opts[66].len + 1);
	    if (str) {
		memcpy(str, opts[66].data, opts[66].len);
		str[opts[66].len] = 0;
	    }	
	} else {
	    str = opts[66].data;
	}
	if (str) {
	    bootp1->sip = pxe_dns(str);
	    if (str != opts[66].data)
		free(str);
	} else {
	    bootp1->sip = pxe->fip;
	}
    } else {
	bootp1->sip = pxe->fip;
    }
    bootp1->gip = pxe->gip;

    ret = dhcp_pack_packet(bootp1, (size_t *)&(pxe->p[5].len), opts);
    if (ret) {
	error("Could not pack packet\n");
	return -ret;	/* dhcp_pack_packet always returns positive errors */
    }
    return ret;
}

/* dhcp_pkt2pxe: Copy packet to PXE's BC data for a ptype packet
 *	Input:
 *	p	Packet data to copy
 *	len	length of data to copy
 *	ptype	Packet type to overwrite
 */
int dhcp_pkt2pxe(pxe_bootp_t *p, size_t len, int ptype)
{
    t_PXENV_GET_CACHED_INFO *ci;
    void *cp;
    int rv = -1;

    if (!(ci = lzalloc(sizeof(t_PXENV_GET_CACHED_INFO)))){
	dprintf("Unable to lzalloc() for PXE call structure\n");
	rv = 1;
	goto ret;
    }
    ci->Status = PXENV_STATUS_FAILURE;
    ci->PacketType = ptype;
    pxe_call(PXENV_GET_CACHED_INFO, ci);

    if (ci->Status != PXENV_STATUS_SUCCESS) {
	dprintf("PXE Get Cached Info failed: %d\n", ci->Status);
	rv = 2;
	goto ret;
    }

    cp = MK_PTR(ci->Buffer.seg, ci->Buffer.offs);
    if (!(memcpy(cp, p, len))) {
	dprintf("Failed to copy packet\n");
	rv = 3;
	goto ret;
    }
ret:
    lfree(ci);
   return rv;
}

int pxechn_mergeopt(struct pxelinux_opt *pxe, int d, int s)
{
    int ret = 0, i;

    if ((d >= PXECHN_NUM_PKT_TYPE) || (s >= PXECHN_NUM_PKT_TYPE) 
	    || (d < 0) || (s < 0)) {
	return -2;
    }
    if (!pxe->p_unpacked[s])
	ret = dhcp_unpack_packet(pxe->p[s].data, pxe->p[s].len, pxe->opts[s]);
    if (ret) {
	error("Could not unpack packet for merge\n");
	printf("Error %d (%d)\n", ret, EINVAL);
	if (ret == EINVAL) {
	    if (pxe->p[s].len < 240)
		printf("Packet %d is too short: %d (240)\n", s, pxe->p[s].len);
	    else if (((const struct dhcp_packet *)(pxe->p[s].data))->magic != htonl(DHCP_VENDOR_MAGIC))
		printf("Packet %d has no magic\n", s);
	    else
		error("Unknown EINVAL error\n");
	} else {
	    error("Unknown error\n");
	}
	return -ret;
    }
    for (i = 0; i < NUM_DHCP_OPTS; i++) {
	if (pxe->opts[d][i].len <= -1) {
	    if (pxe->opts[s][i].len >= 0)
		pxechn_setopt(&(pxe->opts[d][i]), pxe->opts[s][i].data, pxe->opts[s][i].len);
	}
    }
    return 0;
}

/* pxechn: Chainload to new PXE file ourselves
 *	Input:
 *	argc	Count of arguments passed
 *	argv	Values of arguments passed
 *	Returns	0 on success (which should never happen)
 *		1 on loadfile() error
 *		2 if DHCP Option 52 (Option Overload) used file field
 *		-1 on usage error
 */
int pxechn(int argc, char *argv[])
{
    struct pxelinux_opt pxe;
    pxe_bootp_t* p[(2 * PXECHN_NUM_PKT_TYPE)];
    int rv = 0;
    int i;
    struct data_area file;
    struct syslinux_rm_regs regs;

    pxechn_init(&pxe);
    for (i = 0; i < (2 * PXECHN_NUM_PKT_TYPE); i++) {
	p[i] = (pxe_bootp_t *)(pxe.p[i].data);
    }

    /* Parse arguments and patch packet 1 */
    rv = pxechn_args(argc, argv, &pxe);
    dpressanykey(INT_MAX);
    if (rv)
	goto ret;
    pxe_set_regs(&regs);
    /* Load the file late; it's the most time-expensive operation */
    printf("%s: Attempting to load '%s': ", app_name_str, pxe.fn);
    if (loadfile(pxe.fn, &file.data, &file.size)) {
	pxe_error(errno, NULL, NULL);
	rv = -2;
	goto ret;
    }
    puts("loaded.");
    /* we'll be shuffling to the standard location of 7C00h */
    file.base = 0x7C00;
    if ((pxe.wds) || 
	    ((pxe.force) && ((pxe.force & (~PXECHN_FORCE_ALL)) == 0))) {
	printf("Forcing behavior %08X\n", pxe.force);
	// P2 is the same as P3 if no PXE server present.
	if ((pxe.wds) ||
		(pxe.force & PXECHN_FORCE_PKT2)) {
	    pxechn_fill_pkt(&pxe, PXENV_PACKET_TYPE_DHCP_ACK);
	    rv = pxechn_mergeopt(&pxe, 2, 1);
	    if (rv) {
		dprintf("Merge Option returned %d\n", rv);
	    }
	    rv = dhcp_pack_packet(p[5], (size_t *)&(pxe.p[5].len), pxe.opts[2]);
	    rv = dhcp_pkt2pxe(p[5], pxe.p[5].len, PXENV_PACKET_TYPE_DHCP_ACK);
	}
	if (pxe.force & PXECHN_FORCE_PKT1) {
	    puts("Unimplemented force option utilized");
	}
    }
    rv = dhcp_pkt2pxe(p[5], pxe.p[5].len, PXENV_PACKET_TYPE_CACHED_REPLY);
    dprint_pxe_bootp_t(p[5], pxe.p[5].len);
    if ((pxe.wds) ||
	    ((pxe.force) && ((pxe.force & (~PXECHN_FORCE_ALL)) == 0))) {
	// printf("Forcing behavior %08X\n", pxe.force);
	// P2 is the same as P3 if no PXE server present.
	if ((pxe.wds) ||
		(pxe.force & PXECHN_FORCE_PKT2)) {
	    rv = dhcp_pkt2pxe(p[5], pxe.p[5].len, PXENV_PACKET_TYPE_DHCP_ACK);
	}
    } else if (pxe.force) {
	printf("FORCE: bad argument %08X\n", pxe.force);
    }
    printf("\n...Ready to boot:\n");
    if (pxe.wait) {
	pressanykey(INT_MAX);
    } else {
	dpressanykey(INT_MAX);
    }
    if (true) {
	puts("  Attempting to boot...");
	do_boot(&file, 1, &regs);
    }
    /* If failed, copy backup back in and abort */
    dhcp_pkt2pxe(p[2], pxe.p[2].len, PXENV_PACKET_TYPE_CACHED_REPLY);
    if (pxe.force && ((pxe.force & (~PXECHN_FORCE_ALL)) == 0)) {
	if (pxe.force & PXECHN_FORCE_PKT2) {
	    rv = dhcp_pkt2pxe(p[1], pxe.p[1].len, PXENV_PACKET_TYPE_DHCP_ACK);
	}
    }
ret:
    return rv;
}

/* pxe_restart: Restart the PXE environment with a new PXE file
 *	Input:
 *	ifn	Name of file to chainload to in a format PXELINUX understands
 *		This must strictly be TFTP or relative file
 */
int pxe_restart(char *ifn)
{
    int rv = 0;
    struct pxelinux_opt pxe;
    t_PXENV_RESTART_TFTP *pxep;	/* PXENV callback Parameter */

    pxe.fn = ifn;
    pxechn_fill_pkt(&pxe, PXENV_PACKET_TYPE_CACHED_REPLY);
    if (pxe.p[5].data)
	pxe.fip = ( (pxe_bootp_t *)(pxe.p[5].data) )->sip;
    else
	pxe.fip = 0;
    rv = pxechn_parse_fn(pxe.fn, &(pxe.fip), pxe.host, &(pxe.fp));
    if ((rv > 2) || (rv < 0)) {
	printf("%s: ERROR: Unparsable filename argument: '%s'\n\n", app_name_str, pxe.fn);
	goto ret;
    }
    printf("  Attempting to boot '%s'...\n\n", pxe.fn);
    if (!(pxep = lzalloc(sizeof(t_PXENV_RESTART_TFTP)))){
	dprintf("Unable to lzalloc() for PXE call structure\n");
	goto ret;
    }
    pxep->Status = PXENV_STATUS_SUCCESS;	/* PXENV_STATUS_FAILURE */
    strcpy((char *)pxep->FileName, ifn);
    pxep->BufferSize = 0x8000;
    pxep->Buffer = (void *)0x7c00;
    pxep->ServerIPAddress = pxe.fip;
    dprintf("FN='%s'  %08X %08X %08X %08X\n\n", (char *)pxep->FileName,
	pxep->ServerIPAddress, (unsigned int)pxep,
	pxep->BufferSize, (unsigned int)pxep->Buffer);
    dprintf("PXENV_RESTART_TFTP status %d\n", pxep->Status);

    pxe_call(PXENV_RESTART_TFTP, pxep);

    printf("PXENV_RESTART_TFTP returned %d\n", pxep->Status);
    lfree(pxep);

ret:
    return rv;
}

/* pxechn_gpxe: Use gPXE to chainload a new NBP
 *	Input:
 *	argc	Count of arguments passed
 *	argv	Values of arguments passed
 *	Returns	0 on success (which should never happen)
 *		1 on loadfile() error
 *		-1 on usage error
 */
//FIXME:Implement
int pxechn_gpxe(int argc, char *argv[])
{
    int rv = 0;
    struct pxelinux_opt pxe;

    if (argc) {
	printf("%s\n", argv[0]);
	pxechn_args(argc, argv, &pxe);
    }
    return rv;
}

int main(int argc, char *argv[])
{
    int rv= -1;
    int err;
    const struct syslinux_version *sv;

    /* Initialization */
    err = errno;
    console_ansi_raw();	/* sets errno = 9 (EBADF) */
    /* printf("%d %d\n", err, errno); */
    errno = err;
    sv = syslinux_version();
    if (sv->filesystem != SYSLINUX_FS_PXELINUX) {
	printf("%s: May only run in PXELINUX\n", app_name_str);
	argc = 1;	/* prevents further processing to boot */
    }
    if (argc == 2) {
	if ((strcasecmp(argv[1], "-h") == 0) || ((strcmp(argv[1], "-?") == 0))
		|| (strcasecmp(argv[1], "--help") == 0)) {
	    argc = 1;
	} else {
	    rv = pxechn(argc - 1, &argv[1]);
	}
    } else if (argc >= 3) {
	if ((strcmp(argv[1], "-r") == 0)) {
	    if (argc == 3)
		rv = pxe_restart(argv[2]);
	} else {
	    rv = pxechn(argc - 1, &argv[1]);
	}
    }
    if (rv <= -1 ) {
	usage();
	rv = 1;
    }
    return rv;
}
