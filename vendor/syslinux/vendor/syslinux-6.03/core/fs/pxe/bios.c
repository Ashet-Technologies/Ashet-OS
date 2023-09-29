#include <syslinux/firmware.h>
#include <syslinux/memscan.h>
#include <core.h>
#include "pxe.h"
#include <net.h>
#include <minmax.h>
#include <bios.h>
#include <dprintf.h>

static uint16_t real_base_mem;	   /* Amount of DOS memory after freeing */

static bool has_gpxe;
static uint32_t gpxe_funcs;

far_ptr_t StrucPtr;

/*
 * Validity check on possible !PXE structure in buf
 * return 1 for success, 0 for failure.
 *
 */
static int is_pxe(const void *buf)
{
    const struct pxe_t *pxe = buf;
    const uint8_t *p = buf;
    int i = pxe->structlength;
    uint8_t sum = 0;

    if (i < sizeof(struct pxe_t) ||
	memcmp(pxe->signature, "!PXE", 4))
        return 0;

    while (i--)
        sum += *p++;

    return sum == 0;
}

/*
 * Just like is_pxe, it checks PXENV+ structure
 *
 */
static int is_pxenv(const void *buf)
{
    const struct pxenv_t *pxenv = buf;
    const uint8_t *p = buf;
    int i = pxenv->length;
    uint8_t sum = 0;

    /* The pxeptr field isn't present in old versions */
    if (i < offsetof(struct pxenv_t, pxeptr) ||
	memcmp(pxenv->signature, "PXENV+", 6))
        return 0;

    while (i--)
        sum += *p++;

    return sum == 0;
}

/*
 * memory_scan_for_pxe_struct:
 * memory_scan_for_pxenv_struct:
 *
 *	If none of the standard methods find the !PXE/PXENV+ structure,
 *	look for it by scanning memory.
 *
 *	return the corresponding pxe structure if found, or NULL;
 */
static const void *memory_scan(uintptr_t start, int (*func)(const void *))
{
    const char *ptr;

    /* Scan each 16 bytes of conventional memory before the VGA region */
    for (ptr = (const char *)start; ptr < (const char *)0xA0000; ptr += 16) {
        if (func(ptr))
            return ptr;		/* found it! */
	ptr += 16;
    }
    return NULL;
}

static const struct pxe_t *memory_scan_for_pxe_struct(void)
{
    uint16_t start = bios_fbm(); /* Starting segment */

    return memory_scan(start << 10, is_pxe);
}

static const struct pxenv_t *memory_scan_for_pxenv_struct(void)
{
    return memory_scan(0x10000, is_pxenv);
}

static int pxelinux_scan_memory(scan_memory_callback_t callback, void *data)
{
    addr_t start, size;
    int rv = 0;

    if (KeepPXE)
	return 0;

    /*
     * If we are planning on calling unload_pxe() and unmapping the PXE
     * region before we transfer control away from PXELINUX we can mark
     * that region as SMT_TERMINAL to indicate that the region will
     * become free at some point in the future.
     */
    start = bios_fbm() << 10;
    size = (real_base_mem - bios_fbm()) << 10;
    dprintf("Marking PXE region 0x%x - 0x%x as SMT_TERMINAL\n",
	start, start + size);

    callback(data, start, size, SMT_TERMINAL);
    return rv;
}

/*
 * Find the !PXE structure; we search for the following, in order:
 *
 * a. !PXE structure as SS:[SP + 4]
 * b. PXENV+ structure at [ES:BX]
 * c. INT 1Ah AX=0x5650 -> PXENV+
 * d. Search memory for !PXE
 * e. Search memory for PXENV+
 *
 * If we find a PXENV+ structure, we try to find a !PXE structure from
 * if if the API version is 2.1 or later
 *
 */
int pxe_init(bool quiet)
{
    extern void pxe_int1a(void);
    char plan = 'A';
    uint16_t seg, off;
    uint16_t code_seg, code_len;
    uint16_t data_seg, data_len;
    const char *base = GET_PTR(InitStack);
    com32sys_t regs;
    const char *type;
    const struct pxenv_t *pxenv;
    const struct pxe_t *pxe;

    /* Assume API version 2.1 */
    APIVer = 0x201;

    /* Plan A: !PXE structure as SS:[SP + 4] */
    off = *(const uint16_t *)(base + 48);
    seg = *(const uint16_t *)(base + 50);
    pxe = MK_PTR(seg, off);
    if (is_pxe(pxe))
        goto have_pxe;

    /* Plan B: PXENV+ structure at [ES:BX] */
    plan++;
    off = *(const uint16_t *)(base + 24);  /* Original BX */
    seg = *(const uint16_t *)(base + 4);   /* Original ES */
    pxenv = MK_PTR(seg, off);
    if (is_pxenv(pxenv))
        goto have_pxenv;

    /* Plan C: PXENV+ structure via INT 1Ah AX=5650h  */
    plan++;
    memset(&regs, 0, sizeof regs);
    regs.eax.w[0] = 0x5650;
    call16(pxe_int1a, &regs, &regs);
    if (!(regs.eflags.l & EFLAGS_CF) && (regs.eax.w[0] == 0x564e)) {
	off = regs.ebx.w[0];
	seg = regs.es;
	pxenv = MK_PTR(seg, off);
        if (is_pxenv(pxenv))
            goto have_pxenv;
    }

    /* Plan D: !PXE memory scan */
    plan++;
    if ((pxe = memory_scan_for_pxe_struct())) {
	off = OFFS(pxe);
	seg = SEG(pxe);
        goto have_pxe;
    }

    /* Plan E: PXENV+ memory scan */
    plan++;
    if ((pxenv = memory_scan_for_pxenv_struct())) {
	off = OFFS(pxenv);
	seg = SEG(pxenv);
        goto have_pxenv;
    }

    /* Found nothing at all !! */
    if (!quiet)
	ddprintf("No !PXE or PXENV+ API found; we're dead...\n");
    return -1;

 have_pxenv:
    APIVer = pxenv->version;
    if (!quiet)
	ddprintf("Found PXENV+ structure\nPXE API version is %04x\n", APIVer);

    /* if the API version number is 0x0201 or higher, use the !PXE structure */
    if (APIVer >= 0x201) {
	if (pxenv->length >= sizeof(struct pxenv_t)) {
	    pxe = GET_PTR(pxenv->pxeptr);
	    if (is_pxe(pxe))
		goto have_pxe;
	    /*
	     * Nope, !PXE structure missing despite API 2.1+, or at least
	     * the pointer is missing. Do a last-ditch attempt to find it
	     */
	    if ((pxe = memory_scan_for_pxe_struct()))
		goto have_pxe;
	}
	APIVer = 0x200;		/* PXENV+ only, assume version 2.00 */
    }

    /* Otherwise, no dice, use PXENV+ structure */
    data_len = pxenv->undidatasize;
    data_seg = pxenv->undidataseg;
    code_len = pxenv->undicodesize;
    code_seg = pxenv->undicodeseg;
    PXEEntry = pxenv->rmentry;
    type = "PXENV+";

    goto have_entrypoint;

 have_pxe:
    data_len = pxe->seg[PXE_Seg_UNDIData].size;
    data_seg = pxe->seg[PXE_Seg_UNDIData].sel;
    code_len = pxe->seg[PXE_Seg_UNDICode].size;
    code_seg = pxe->seg[PXE_Seg_UNDICode].sel;
    PXEEntry = pxe->entrypointsp;
    type = "!PXE";

 have_entrypoint:
    StrucPtr.offs = off;
    StrucPtr.seg  = seg;

    if (!quiet) {
	ddprintf("%s entry point found (we hope) at %04X:%04X via plan %c\n",
	       type, PXEEntry.seg, PXEEntry.offs, plan);
	ddprintf("UNDI code segment at %04X len %04X\n", code_seg, code_len);
	ddprintf("UNDI data segment at %04X len %04X\n", data_seg, data_len);
    }

    syslinux_memscan_new(pxelinux_scan_memory);

    code_seg = code_seg + ((code_len + 15) >> 4);
    data_seg = data_seg + ((data_len + 15) >> 4);

    real_base_mem = max(code_seg, data_seg) >> 6; /* Convert to kilobytes */

    probe_undi();

    return 0;
}

/*
 * See if we have gPXE
 */
void gpxe_init(void)
{
    int err;
    static __lowmem struct s_PXENV_FILE_API_CHECK api_check;

    if (APIVer >= 0x201) {
	api_check.Size = sizeof api_check;
	api_check.Magic = 0x91d447b2;
	err = pxe_call(PXENV_FILE_API_CHECK, &api_check);
	if (!err && api_check.Magic == 0xe9c17b20)
	    gpxe_funcs = api_check.APIMask;
    }

    /* Necessary functions for us to use the gPXE file API */
    has_gpxe = (~gpxe_funcs & 0x4b) == 0;
}


/**
 * Get a DHCP packet from the PXE stack into a lowmem buffer
 *
 * @param:  type,  packet type
 * @return: buffer size
 *
 */
static int pxe_get_cached_info(int type, void *buf, size_t bufsiz)
{
    int err;
    static __lowmem struct s_PXENV_GET_CACHED_INFO get_cached_info;
    ddprintf(" %02x", type);

    memset(&get_cached_info, 0, sizeof get_cached_info);
    get_cached_info.PacketType  = type;
    get_cached_info.BufferSize  = bufsiz;
    get_cached_info.Buffer      = FAR_PTR(buf);
    err = pxe_call(PXENV_GET_CACHED_INFO, &get_cached_info);
    if (err) {
        ddprintf("PXE API call failed, error  %04x\n", err);
	kaboom();
    }

    return get_cached_info.BufferSize;
}

/*
 * This function unloads the PXE and UNDI stacks and
 * unclaims the memory.
 */
__export void unload_pxe(uint16_t flags)
{
    /* PXE unload sequences */
    /*
     * iPXE does:
     * UNDI_SHUTDOWN, UNDI_CLEANUP, STOP_UNDI
     * Older Syslinux did:
     * UDP_CLOSE, UNDI_SHUTDOWN, UNLOAD_STACK, STOP_UNDI/UNDI_CLEANUP
     */
    static const uint8_t new_api_unload[] = {
	PXENV_UNDI_SHUTDOWN, PXENV_UNLOAD_STACK, PXENV_STOP_UNDI, 0
    };
    static const uint8_t old_api_unload[] = {
	PXENV_UNDI_SHUTDOWN, PXENV_UNLOAD_STACK, PXENV_UNDI_CLEANUP, 0
    };

    unsigned int api;
    const uint8_t *api_ptr;
    int err;
    size_t int_addr;
    static __lowmem union {
	struct s_PXENV_UNDI_SHUTDOWN undi_shutdown;
	struct s_PXENV_UNLOAD_STACK unload_stack;
	struct s_PXENV_STOP_UNDI stop_undi;
	struct s_PXENV_UNDI_CLEANUP undi_cleanup;
	uint16_t Status;	/* All calls have this as the first member */
    } unload_call;

    dprintf("Called unload_pxe()...\n");
    dprintf("FBM before unload = %d\n", bios_fbm());

    err = reset_pxe();

    dprintf("FBM after reset_pxe = %d, err = %d\n", bios_fbm(), err);

    /* If we want to keep PXE around, we still need to reset it */
    if (flags || err)
	return;

    dprintf("APIVer = %04x\n", APIVer);

    api_ptr = APIVer >= 0x0200 ? new_api_unload : old_api_unload;
    while((api = *api_ptr++)) {
	dprintf("PXE call %04x\n", api);
	memset(&unload_call, 0, sizeof unload_call);
	err = pxe_call(api, &unload_call);
	if (err || unload_call.Status != PXENV_STATUS_SUCCESS) {
	    ddprintf("PXE unload API call %04x failed: 0x%x\n",
		   api, unload_call.Status);
	    goto cant_free;
	}
    }

    api = 0xff00;
    if (real_base_mem <= bios_fbm()) {  /* Sanity check */
	dprintf("FBM %d < real_base_mem %d\n", bios_fbm(), real_base_mem);
	goto cant_free;
    }
    api++;

    /* Check that PXE actually unhooked the INT 0x1A chain */
    int_addr = (size_t)GET_PTR(*(far_ptr_t *)(4 * 0x1a));
    int_addr >>= 10;
    if (int_addr >= real_base_mem || int_addr < bios_fbm()) {
	set_bios_fbm(real_base_mem);
	dprintf("FBM after unload_pxe = %d\n", bios_fbm());
	return;
    }

    dprintf("Can't free FBM, real_base_mem = %d, "
	    "FBM = %d, INT 1A = %08x (%d)\n",
	    real_base_mem, bios_fbm(),
	    *(uint32_t *)(4 * 0x1a), int_addr);

cant_free:
    ddprintf("Failed to free base memory error %04x-%08x (%d/%dK)\n",
	   api, *(uint32_t *)(4 * 0x1a), bios_fbm(), real_base_mem);
    return;
}

extern const char bdhcp_data[], adhcp_data[];
extern const uint32_t bdhcp_len, adhcp_len;

void net_parse_dhcp(void)
{
    int pkt_len;
    struct bootp_t *bp;
    const size_t dhcp_max_packet = 4096;

    bp = lmalloc(dhcp_max_packet);
    if (!bp) {
	ddprintf("Out of low memory\n");
	kaboom();
    }

    *LocalDomain = 0;   /* No LocalDomain received */

    /*
     * Parse any "before" hardcoded options
     */
    dprintf("DHCP: bdhcp_len = %d\n", bdhcp_len);
    parse_dhcp_options(bdhcp_data, bdhcp_len, 0);

    /*
     * Get the DHCP client identifiers (query info 1)
     */
    ddprintf("Getting cached packet ");
    pkt_len = pxe_get_cached_info(1, bp, dhcp_max_packet);
    parse_dhcp(bp, pkt_len);

    /*
     * We don't use flags from the request packet, so
     * this is a good time to initialize DHCPMagic...
     * Initialize it to 1 meaning we will accept options found;
     * in earlier versions of PXELINUX bit 0 was used to indicate
     * we have found option 208 with the appropriate magic number;
     * we no longer require that, but MAY want to re-introduce
     * it in the future for vendor encapsulated options.
     */
    *(char *)&DHCPMagic = 1;

    /*
     * Get the BOOTP/DHCP packet that brought us file (and an IP
     * address). This lives in the DHCPACK packet (query info 2)
     */
    pkt_len = pxe_get_cached_info(2, bp, dhcp_max_packet);
    parse_dhcp(bp, pkt_len);
    /*
     * Save away MAC address (assume this is in query info 2. If this
     * turns out to be problematic it might be better getting it from
     * the query info 1 packet
     */
    MAC_len = bp->hardlen > 16 ? 0 : bp->hardlen;
    MAC_type = bp->hardware;
    memcpy(MAC, bp->macaddr, MAC_len);

    /*
     * Get the boot file and other info. This lives in the CACHED_REPLY
     * packet (query info 3)
     */
    pkt_len = pxe_get_cached_info(3, bp, dhcp_max_packet);
    parse_dhcp(bp, pkt_len);
    ddprintf("\n");

    /*
     * Parse any "after" hardcoded options
     */
    dprintf("DHCP: adhcp_len = %d\n", adhcp_len);
    parse_dhcp_options(adhcp_data, adhcp_len, 0);

    lfree(bp);
}
