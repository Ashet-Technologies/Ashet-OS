/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Pierre-Alexandre Meyer
 *
 *   Some parts borrowed from meminfo.c32:
 *
 *   Copyright 2003-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 *
 *   Some parts borrowed from Linux:
 *
 *   Copyright (C) 1991, 1992 Linus Torvalds
 *   Copyright 2007 rPath, Inc. - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author H. Peter Anvin
 *
 *   Interrupt list from Ralf Brown (http://www.cs.cmu.edu/~ralf/files.html)
 *
 *   This file is part of Syslinux, and is made available under
 *   the terms of the GNU General Public License version 2.
 *
 * ----------------------------------------------------------------------- */

#include <stdint.h>
#include <com32.h>
#include <string.h>
#include <memory.h>

const char *const e820_types[] = {
    "usable",
    "reserved",
    "ACPI reclaim",
    "ACPI NVS",
    "unusable",
};

struct e820_ext_entry {
    struct e820entry std;
    uint32_t ext_flags;
} __attribute__ ((packed));

#define SMAP	0x534d4150	/* ASCII "SMAP" */

void get_type(int type, char *type_ptr, int type_ptr_sz)
{
    unsigned int real_type = type - 1;
    if (real_type < sizeof(e820_types) / sizeof(e820_types[0]))
	strlcpy(type_ptr, e820_types[real_type], type_ptr_sz);
}

/**
 *INT 15 - newer BIOSes - GET SYSTEM MEMORY MAP
 *	AX = E820h
 *	EAX = 0000E820h
 *	EDX = 534D4150h ('SMAP')
 *	EBX = continuation value or 00000000h to start at beginning of map
 *	ECX = size of buffer for result, in bytes (should be >= 20 bytes)
 *	ES:DI -> buffer for result (see #00581)
 *
 * Return: CF clear if successful
 *	    EAX = 534D4150h ('SMAP')
 *	    ES:DI buffer filled
 *	    EBX = next offset from which to copy or 00000000h if all done
 *	    ECX = actual length returned in bytes
 *	CF set on error
 *	    AH = error code (86h) (see #00496 at INT 15/AH=80h)
 *
 * Notes: originally introduced with the Phoenix BIOS v4.0, this function is
 *	  now supported by most newer BIOSes, since various versions of Windows
 *	  call it to find out about the system memory
 *	a maximum of 20 bytes will be transferred at one time, even if ECX is
 *	  higher; some BIOSes (e.g. Award Modular BIOS v4.50PG) ignore the
 *	  value of ECX on entry, and always copy 20 bytes
 *	some BIOSes expect the high word of EAX to be clear on entry, i.e.
 *	  EAX=0000E820h
 *	if this function is not supported, an application should fall back
 *	  to AX=E802h, AX=E801h, and then AH=88h
 *	the BIOS is permitted to return a nonzero continuation value in EBX
 *	  and indicate that the end of the list has already been reached by
 *	  returning with CF set on the next iteration
 *	this function will return base memory and ISA/PCI memory contiguous
 *	  with base memory as normal memory ranges; it will indicate
 *	  chipset-defined address holes which are not in use and motherboard
 *	  memory-mapped devices, and all occurrences of the system BIOS as
 *	  reserved; standard PC address ranges will not be reported
 **/
void detect_memory_e820(struct e820entry *desc, int size_map, int *size_found)
{
    int count = 0;
    static struct e820_ext_entry buf;	/* static so it is zeroed */
    void *bounce;

    com32sys_t ireg, oreg;
    memset(&ireg, 0, sizeof ireg);

    bounce = lmalloc(sizeof buf);
    if (!bounce)
	goto out;

    ireg.eax.w[0] = 0xe820;
    ireg.edx.l = SMAP;
    ireg.ecx.l = sizeof(struct e820_ext_entry);
    ireg.edi.w[0] = OFFS(bounce);
    ireg.es = SEG(bounce);

    /*
     * Set this here so that if the BIOS doesn't change this field
     * but still doesn't change %ecx, we're still okay...
     */
    memset(&buf, 0, sizeof buf);
    buf.ext_flags = 1;

    do {
	memcpy(bounce, &buf, sizeof buf);

	/* Important: %edx and %esi are clobbered by some BIOSes,
	   so they must be either used for the error output
	   or explicitly marked clobbered.  Given that, assume there
	   is something out there clobbering %ebp and %edi, too. */
	__intcall(0x15, &ireg, &oreg);

	/* Some BIOSes stop returning SMAP in the middle of
	   the search loop.  We don't know exactly how the BIOS
	   screwed up the map at that point, we might have a
	   partial map, the full map, or complete garbage, so
	   just return failure. */
	if (oreg.eax.l != SMAP) {
	    count = 0;
	    break;
	}

	if (oreg.eflags.l & EFLAGS_CF || oreg.ecx.l < 20)
	    break;

	memcpy(&buf, bounce, sizeof buf);

	/*
	 * ACPI 3.0 added the extended flags support.  If bit 0
	 * in the extended flags is zero, we're supposed to simply
	 * ignore the entry -- a backwards incompatible change!
	 */
	if (oreg.ecx.l > 20 && !(buf.ext_flags & 1))
	    continue;

	memcpy(&desc[count], &buf, sizeof buf);
	count++;

	/* Set continuation value */
	ireg.ebx.l = oreg.ebx.l;
    } while (ireg.ebx.l && count < size_map);

out:
    lfree(bounce);
    *size_found = count;
}

/**
 * detect_memory_e801
 *
 *INT 15 - Phoenix BIOS v4.0 - GET MEMORY SIZE FOR >64M CONFIGURATIONS
 *	AX = E801h
 *
 * Return: CF clear if successful
 *	    AX = extended memory between 1M and 16M, in K (max 3C00h = 15MB)
 *	    BX = extended memory above 16M, in 64K blocks
 *	    CX = configured memory 1M to 16M, in K
 *	    DX = configured memory above 16M, in 64K blocks
 *	CF set on error
 *
 * Notes: supported by the A03 level (6/14/94) and later XPS P90 BIOSes, as well
 *	as the Compaq Contura, 3/8/93 DESKPRO/i, and 7/26/93 LTE Lite 386 ROM
 *	BIOS
 *	supported by AMI BIOSes dated 8/23/94 or later
 *	on some systems, the BIOS returns AX=BX=0000h; in this case, use CX
 *	  and DX instead of AX and BX
 *	this interface is used by Windows NT 3.1, OS/2 v2.11/2.20, and is
 *	  used as a fall-back by newer versions if AX=E820h is not supported
 *	this function is not used by MS-DOS 6.0 HIMEM.SYS when an EISA machine
 *	  (for example with parameter /EISA) (see also MEM F000h:FFD9h), or no
 *	  Compaq machine was detected, or parameter /NOABOVE16 was given.
 **/
int detect_memory_e801(int *mem_size_below_16, int *mem_size_above_16)
{
    com32sys_t ireg, oreg;
    memset(&ireg, 0, sizeof ireg);

    ireg.eax.w[0] = 0xe801;

    __intcall(0x15, &ireg, &oreg);

    if (oreg.eflags.l & EFLAGS_CF)
	return -1;

    if (oreg.eax.w[0] > 0x3c00)
	return -1;		/* Bogus! */

    /* Linux seems to use ecx and edx by default if they are defined */
    if (oreg.eax.w[0] || oreg.eax.w[0]) {
	oreg.eax.w[0] = oreg.ecx.w[0];
	oreg.ebx.w[0] = oreg.edx.w[0];
    }

    *mem_size_below_16 = oreg.eax.w[0];	/* 1K blocks */
    *mem_size_above_16 = oreg.ebx.w[0];	/* 64K blocks */

    return 0;
}

int detect_memory_88(int *mem_size)
{
    com32sys_t ireg, oreg;
    memset(&ireg, 0, sizeof ireg);

    ireg.eax.w[0] = 0x8800;

    __intcall(0x15, &ireg, &oreg);

    if (oreg.eflags.l & EFLAGS_CF)
	return -1;

    *mem_size = oreg.eax.w[0];
    return 0;
}

/*
 * Sanitize the BIOS e820 map.
 *
 * This code come from the memtest86 project. It have been adjusted to match
 * the syslinux environement.
 * Some e820 responses include overlapping entries.  The following 
 * replaces the original e820 map with a new one, removing overlaps.
 * 
 * The following stuff could be merge once the addr_t will be set to 64bits.
 * syslinux_scan_memory can be used for that purpose 
 */
int sanitize_e820_map(struct e820entry *orig_map, struct e820entry *new_bios,
		      short old_nr)
{
    struct change_member {
	struct e820entry *pbios;	/* pointer to original bios entry */
	unsigned long long addr;	/* address for this change point */
    };
    struct change_member change_point_list[2 * E820MAX];
    struct change_member *change_point[2 * E820MAX];
    struct e820entry *overlap_list[E820MAX];
    struct e820entry biosmap[E820MAX];
    struct change_member *change_tmp;
    unsigned long current_type, last_type;
    unsigned long long last_addr;
    int chgidx, still_changing;
    int overlap_entries;
    int new_bios_entry;
    int i;

    /*
       Visually we're performing the following (1,2,3,4 = memory types)...
       Sample memory map (w/overlaps):
       ____22__________________
       ______________________4_
       ____1111________________
       _44_____________________
       11111111________________
       ____________________33__
       ___________44___________
       __________33333_________
       ______________22________
       ___________________2222_
       _________111111111______
       _____________________11_
       _________________4______

       Sanitized equivalent (no overlap):
       1_______________________
       _44_____________________
       ___1____________________
       ____22__________________
       ______11________________
       _________1______________
       __________3_____________
       ___________44___________
       _____________33_________
       _______________2________
       ________________1_______
       _________________4______
       ___________________2____
       ____________________33__
       ______________________4_
     */
    /* First make a copy of the map */
    for (i = 0; i < old_nr; i++) {
	biosmap[i].addr = orig_map[i].addr;
	biosmap[i].size = orig_map[i].size;
	biosmap[i].type = orig_map[i].type;
    }

    /* bail out if we find any unreasonable addresses in bios map */
    for (i = 0; i < old_nr; i++) {
	if (biosmap[i].addr + biosmap[i].size < biosmap[i].addr)
	    return 0;
    }

    /* create pointers for initial change-point information (for sorting) */
    for (i = 0; i < 2 * old_nr; i++)
	change_point[i] = &change_point_list[i];

    /* record all known change-points (starting and ending addresses) */
    chgidx = 0;
    for (i = 0; i < old_nr; i++) {
	change_point[chgidx]->addr = biosmap[i].addr;
	change_point[chgidx++]->pbios = &biosmap[i];
	change_point[chgidx]->addr = biosmap[i].addr + biosmap[i].size;
	change_point[chgidx++]->pbios = &biosmap[i];
    }

    /* sort change-point list by memory addresses (low -> high) */
    still_changing = 1;
    while (still_changing) {
	still_changing = 0;
	for (i = 1; i < 2 * old_nr; i++) {
	    /* if <current_addr> > <last_addr>, swap */
	    /* or, if current=<start_addr> & last=<end_addr>, swap */
	    if ((change_point[i]->addr < change_point[i - 1]->addr) ||
		((change_point[i]->addr == change_point[i - 1]->addr) &&
		 (change_point[i]->addr == change_point[i]->pbios->addr) &&
		 (change_point[i - 1]->addr !=
		  change_point[i - 1]->pbios->addr))
		) {
		change_tmp = change_point[i];
		change_point[i] = change_point[i - 1];
		change_point[i - 1] = change_tmp;
		still_changing = 1;
	    }
	}
    }

    /* create a new bios memory map, removing overlaps */
    overlap_entries = 0;	/* number of entries in the overlap table */
    new_bios_entry = 0;		/* index for creating new bios map entries */
    last_type = 0;		/* start with undefined memory type */
    last_addr = 0;		/* start with 0 as last starting address */
    /* loop through change-points, determining affect on the new bios map */
    for (chgidx = 0; chgidx < 2 * old_nr; chgidx++) {
	/* keep track of all overlapping bios entries */
	if (change_point[chgidx]->addr == change_point[chgidx]->pbios->addr) {
	    /* add map entry to overlap list (> 1 entry implies an overlap) */
	    overlap_list[overlap_entries++] = change_point[chgidx]->pbios;
	} else {
	    /* remove entry from list (order independent, so swap with last) */
	    for (i = 0; i < overlap_entries; i++) {
		if (overlap_list[i] == change_point[chgidx]->pbios)
		    overlap_list[i] = overlap_list[overlap_entries - 1];
	    }
	    overlap_entries--;
	}
	/* if there are overlapping entries, decide which "type" to use */
	/* (larger value takes precedence -- 1=usable, 2,3,4,4+=unusable) */
	current_type = 0;
	for (i = 0; i < overlap_entries; i++)
	    if (overlap_list[i]->type > current_type)
		current_type = overlap_list[i]->type;
	/* continue building up new bios map based on this information */
	if (current_type != last_type) {
	    if (last_type != 0) {
		new_bios[new_bios_entry].size =
		    change_point[chgidx]->addr - last_addr;
		/* move forward only if the new size was non-zero */
		if (new_bios[new_bios_entry].size != 0)
		    if (++new_bios_entry >= E820MAX)
			break;	/* no more space left for new bios entries */
	    }
	    if (current_type != 0) {
		new_bios[new_bios_entry].addr = change_point[chgidx]->addr;
		new_bios[new_bios_entry].type = current_type;
		last_addr = change_point[chgidx]->addr;
	    }
	    last_type = current_type;
	}
    }
    return (new_bios_entry);
}

/* The following stuff could be merge once the addr_t will be set to 64bits.
 * syslinux_scan_memory can be used for that purpose */
unsigned long detect_memsize(void)
{
    unsigned long memory_size = 0;

    /* Try to detect memory via e820 */
    struct e820entry map[E820MAX];
    int count = 0;
    detect_memory_e820(map, E820MAX, &count);
    memory_size = memsize_e820(map, count);
    if (memory_size > 0)
	return memory_size;

    /*e820 failed, let's try e801 */
    int mem_low, mem_high = 0;
    if (!detect_memory_e801(&mem_low, &mem_high))
	return mem_low + (mem_high << 6);

    /*e801 failed, let's try e88 */
    int mem_size = 0;
    if (!detect_memory_88(&mem_size))
	return mem_size;

    /* We were enable to detect any kind of memory */
    return 0;
}

/* The following stuff could be merge once the addr_t will be set to 64bits.
 * syslinux_scan_memory can be used for that purpose */
unsigned long memsize_e820(struct e820entry *e820, int e820_nr)
{
    int i, n, nr;
    unsigned long memory_size = 0;
    struct e820entry nm[E820MAX];

    /* Clean up, adjust and copy the BIOS-supplied E820-map. */
    nr = sanitize_e820_map(e820, nm, e820_nr);

    /* If there is not a good 820 map returning 0 to indicate 
       that we don't have any idea of the amount of ram we have */
    if (nr < 1 || nr > E820MAX) {
	return 0;
    }

    /* Build the memory map for testing */
    n = 0;
    for (i = 0; i < nr; i++) {
	if (nm[i].type == E820_RAM || nm[i].type == E820_ACPI) {
	    unsigned long long start;
	    unsigned long long end;
	    start = nm[i].addr;
	    end = start + nm[i].size;

	    /* Don't ever use memory between 640 and 1024k */
	    if (start > RES_START && start < RES_END) {
		if (end < RES_END) {
		    continue;
		}
		start = RES_END;
	    }
	    if (end > RES_START && end < RES_END) {
		end = RES_START;
	    }
	    memory_size += (end >> 12) - ((start + 4095) >> 12);
	    n++;
	} else if (nm[i].type == E820_NVS) {
	    memory_size += nm[i].size >> 12;
	}
    }
    return memory_size * 4;
}
