/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2011 Shao Miller - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/****
 * @file ifmemdsk.c
 *
 * This COM32 module detects if there are MEMDISKs established.
 */

static const char usage_text[] = "\
Usage:\n\
  ifmemdsk.c32 [<option> [...]] --info [<option> [...]]\n\
  ifmemdsk.c32 [<option> [...]] [<detected_cmd>] -- [<not_detected_cmd>]\n\
\n\
Options:\n\
  --info  . . . . . Displays info about MEMDISK(s)\n\
  --safe-hooks . .  Will scan INT 13h \"safe hook\" chain\n\
  --mbfts . . . . . Will scan memory for MEMDISK mBFTs\n\
  --no-sequential   Suppresses probing all drive numbers\n\
\n\
If a MEMDISK is found, or if a particular MEMDISK is sought by the options\n\
and is found, then the 'detected_cmd' action will be taken, else the\n\
'not_detected_cmd' action will be taken.\n\
\n";

#include <stdio.h>
#include <string.h>
#include <alloca.h>
#include <com32.h>
#include <console.h>
#include <syslinux/boot.h>

/* Pull in MEMDISK common structures */
#include "../../memdisk/mstructs.h"

/*** Macros */
#define M_GET_DRIVE_PARAMS (0x08)
#define M_SEGOFFTOPTR(seg, off) (((seg) << 4) + (off))
#define M_INT13H M_SEGOFFTOPTR(0x0000, 0x0013 * 4)
#define M_FREEBASEMEM M_SEGOFFTOPTR(0x0040, 0x0013)
#define M_TOP M_SEGOFFTOPTR(0x9FFF, 0x0000)

/*** Object types */
typedef struct mdi s_mdi;
typedef real_addr_t u_segoff;
typedef struct safe_hook s_safe_hook;
typedef struct mBFT s_mbft;

/*** Function types */
typedef int f_find(void);

/*** Function declarations */
static const s_mdi * installation_check(int);
static f_find scan_drives;
static f_find walk_safe_hooks;
static const s_safe_hook * is_safe_hook(const void *);
static const s_mdi * is_memdisk_hook(const s_safe_hook *);
static f_find scan_mbfts;
static const s_mbft * is_mbft(const void *);
static f_find do_nothing;
static void memdisk_info(const s_mdi *);
static void boot_args(char **);
static const char * bootloadername(uint8_t);

/*** Structure/union definitions */

/*** Objects */
static int show_info = 0;

/*** Function definitions */

int main(int argc, char ** argv) {
    static f_find * do_scan_drives = scan_drives;
    static f_find * do_walk_safe_hooks = do_nothing;
    static f_find * do_scan_mbfts = do_nothing;
    char ** detected_cmd;
    char ** not_detected_cmd;
    char ** cmd;
    char ** cur_arg;
    int show_usage;
    int found;

    (void) argc;

    openconsole(&dev_null_r, &dev_stdcon_w);

    detected_cmd = NULL;
    not_detected_cmd = NULL;
    show_usage = 1;
    for (cur_arg = argv + 1; *cur_arg; ++cur_arg) {
        /* Check for command divider */
        if (!strcmp(*cur_arg, "--")) {
            show_usage = 0;
            *cur_arg = NULL;
            not_detected_cmd = cur_arg + 1;
            break;
          }

        /* Check for '--info' */
        if (!strcmp(*cur_arg, "--info")) {
            show_usage = 0;
            show_info = 1;
            continue;
          }

        /* Other options */
        if (!strcmp(*cur_arg, "--no-sequential")) {
            do_scan_drives = do_nothing;
            continue;
          }

        if (!strcmp(*cur_arg, "--safe-hooks")) {
            do_walk_safe_hooks = walk_safe_hooks;
            continue;
          }

        if (!strcmp(*cur_arg, "--mbfts")) {
            do_scan_mbfts = scan_mbfts;
            continue;
          }

        /* Check for invalid option */
        if (!memcmp(*cur_arg, "--", sizeof "--" - 1)) {
            puts("Invalid option!");
            show_usage = 1;
            break;
          }

        /* Set 'detected_cmd' if it's null */
        if (!detected_cmd)
          detected_cmd = cur_arg;

        continue;
      }

    if (show_usage) {
        fprintf(stderr, usage_text);
        return 1;
      }

    found = 0;
    found += do_walk_safe_hooks();
    found += do_scan_mbfts();
    found += do_scan_drives();

    cmd = found ? detected_cmd : not_detected_cmd;
    if (cmd && *cmd)
      boot_args(cmd);

    return 0;
  }

static const s_mdi * installation_check(int drive) {
    com32sys_t params, results;
    int found;

    /* Set parameters for INT 0x13 call */
    memset(&params, 0, sizeof params);
    params.eax.w[0] = M_GET_DRIVE_PARAMS << 8;
    params.edx.w[0] = drive;
    /* 'ME' 'MD' 'IS' 'K?' */
    params.eax.w[1] = 0x454D;
    params.ecx.w[1] = 0x444D;
    params.edx.w[1] = 0x5349;
    params.ebx.w[1] = 0x3F4B;

    /* Perform the call */
    __intcall(0x13, &params, &results);

    /* Check result */
    found = (
        /* '!M' 'EM' 'DI' 'SK' */
        results.eax.w[1] == 0x4D21 &&
        results.ecx.w[1] == 0x4D45 &&
        results.edx.w[1] == 0x4944 &&
        results.ebx.w[1] == 0x4B53
      );

    if (found)
      return MK_PTR(results.es, results.edi.w[0]);

    return NULL;
  }

static int scan_drives(void) {
    int found, drive;
    const s_mdi * mdi;

    for (found = drive = 0; drive <= 0xFF; ++drive) {
        mdi = installation_check(drive);
        if (!mdi)
          continue;

        memdisk_info(mdi);
        ++found;
        continue;
      }

    return found;
  }

static int walk_safe_hooks(void) {
    static const u_segoff * const int13 = (void *) M_INT13H;
    const void * addr;
    int found;
    const s_safe_hook * hook;
    const s_mdi * mdi;

    /* INT 0x13 vector */
    addr = MK_PTR(int13->seg_off.segment, int13->seg_off.offset);
    found = 0;
    while (addr) {
        hook = is_safe_hook(addr);
        if (!hook)
          break;

        mdi = is_memdisk_hook(hook);
        if (mdi) {
            memdisk_info(mdi);
            ++found;
          }

        addr = MK_PTR(
            hook->old_hook.seg_off.segment,
            hook->old_hook.seg_off.offset
          );
        continue;
      }
    return found;
  }

static const s_safe_hook * is_safe_hook(const void * addr) {
    static const char magic[] = "$INT13SF";
    const s_safe_hook * const test = addr;

    if (memcmp(test->signature, magic, sizeof magic - 1))
      return NULL;

    return test;
  }

static const s_mdi * is_memdisk_hook(const s_safe_hook * hook) {
    static const char magic[] = "MEMDISK";
    const s_mbft * mbft;

    if (memcmp(hook->vendor, magic, sizeof magic - 1))
      return NULL;

    /* An mBFT is always aligned */
    mbft = MK_PTR(hook->mbft >> 4, 0);
    return &mbft->mdi;
  }

static int scan_mbfts(void) {
    static const uint16_t * const free_base_mem = (void *) M_FREEBASEMEM;
    static const void * const top = (void *) M_TOP;
    const void * addr;
    const s_mbft * mbft;
    int found;

    found = 0;
    for (addr = MK_PTR(*free_base_mem << 4, 0); addr < top; addr += 1 << 4) {
        if (!(mbft = is_mbft(addr)))
          continue;

        memdisk_info(&mbft->mdi);
        ++found;
        continue;
      }

    return found;
  }

static const s_mbft * is_mbft(const void * addr) {
    static const char magic[] = "mBFT";
    const s_mbft * const test = addr;
    const uint8_t * ptr, * end;
    uint8_t chksum;

    if (memcmp(test->acpi.signature, magic, sizeof magic - 1))
      return NULL;

    if (test->acpi.length != sizeof *test)
      return NULL;

    end = (void *) (test + 1);
    chksum = 0;
    for (ptr = addr; ptr < end; ++ptr)
      chksum += *ptr;
    if (chksum)
      return NULL;

    /* Looks like it's an mBFT! */
    return test;
  }

static int do_nothing(void) {
    return 0;
  }

static void memdisk_info(const s_mdi * mdi) {
    const char * cmdline;

    if (!show_info)
      return;

    cmdline = MK_PTR(
        mdi->cmdline.seg_off.segment,
        mdi->cmdline.seg_off.offset
      );
    printf(
        "Found MEMDISK version %u.%02u:\n"
        "  diskbuf == 0x%08X, disksize == %u sectors\n"
        "  bootloaderid == 0x%02X (%s),\n"
        "  cmdline: %s\n",
        mdi->version_major,
        mdi->version_minor,
        mdi->diskbuf,
        mdi->disksize,
        mdi->bootloaderid,
        bootloadername(mdi->bootloaderid),
        cmdline
      );
    return;
  }

/* This function copyright H. Peter Anvin */
static void boot_args(char **args)
{
    int len = 0, a = 0;
    char **pp;
    const char *p;
    char c, *q, *str;

    for (pp = args; *pp; pp++)
	len += strlen(*pp) + 1;

    q = str = alloca(len);
    for (pp = args; *pp; pp++) {
	p = *pp;
	while ((c = *p++))
	    *q++ = c;
	*q++ = ' ';
	a = 1;
    }
    q -= a;
    *q = '\0';

    if (!str[0])
	syslinux_run_default();
    else
	syslinux_run_command(str);
}

/* This function copyright H. Peter Anvin */
static const char *bootloadername(uint8_t id)
{
    static const struct {
	uint8_t id, mask;
	const char *name;
    } *lp, list[] = {
	{0x00, 0xf0, "LILO"}, 
	{0x10, 0xf0, "LOADLIN"},
	{0x31, 0xff, "SYSLINUX"},
	{0x32, 0xff, "PXELINUX"},
	{0x33, 0xff, "ISOLINUX"},
	{0x34, 0xff, "EXTLINUX"},
	{0x30, 0xf0, "Syslinux family"},
	{0x40, 0xf0, "Etherboot"},
	{0x50, 0xf0, "ELILO"},
	{0x70, 0xf0, "GrUB"},
	{0x80, 0xf0, "U-Boot"},
	{0xA0, 0xf0, "Gujin"},
	{0xB0, 0xf0, "Qemu"},
	{0x00, 0x00, "unknown"}
    };

    for (lp = list;; lp++) {
	if (((id ^ lp->id) & lp->mask) == 0)
	    return lp->name;
    }
}

