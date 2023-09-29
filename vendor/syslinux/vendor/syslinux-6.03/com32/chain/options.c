/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2003-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
 *   Copyright 2010 Shao Miller
 *   Copyright 2010-2012 Michal Soltys
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
 * ----------------------------------------------------------------------- */

#include <syslinux/movebits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "chain.h"
#include "partiter.h"
#include "utility.h"
#include "options.h"

struct options opt;

static int soi_s2n(char *ptr,
			addr_t *seg,
			addr_t *off,
			addr_t *ip,
			addr_t def)
{
    addr_t segval, offval, ipval, val;
    char *p;

    /* defaults */
    segval = 0;
    offval = def;
    ipval = def;

    segval = strtoul(ptr, &p, 0);
    if (p[0] == ':' && p[1] && p[1] != ':')
	offval = strtoul(p+1, &p, 0);
    if (p[0] == ':' && p[1] && p[1] != ':')
	ipval = strtoul(p+1, NULL, 0);

    /* verify if load address is within [dosmin, dosmax) */
    val = (segval << 4) + offval;

    if (val < dosmin || val >= dosmax) {
	error("Invalid seg:off:* address specified.");
	goto bail;
    }

    /*
     * verify if jump address is within [dosmin, dosmax) and offset is 16bit
     * sane
     */
    val = (segval << 4) + ipval;

    if (ipval > 0xFFFE || val < dosmin || val >= dosmax) {
	error("Invalid seg:*:ip address specified.");
	goto bail;
    }

    if (seg)
	*seg = segval;
    if (off)
	*off = offval;
    if (ip)
	*ip  = ipval;

    return 0;
bail:
    return -1;
}

static void usage(void)
{
    size_t i;
    static const char *const usage[] = {
"Usage:",
"",
"  disk + partition selection:",
"        chain.c32 [options]",
"        chain.c32 hd#[,#] [options]",
"        chain.c32 fd#[,#] [options]",
"        chain.c32 mbr=<id>[,#] [options]",
"        chain.c32 guid=<guid>[,#] [options]",
"        chain.c32 boot[,#] [options]",
"",
"  direct partition selection:",
"        chain.c32 guid=<guid> [options]",
"        chain.c32 label=<label> [options]",
"        chain.c32 fs [options]",
"",
"You can use ':' instead of '=' and ' ' instead of ','.",
"The default is 'boot,0'.",
"",
"Options:",
"  sect[=<s[:o[:i]]>]   Load sector at <s:o>, jump to <s:i>",
"                       - defaults to 0:0x7C00:0x7C00",
"                       - omitted o/i values default to 0",
"  maps                 Map loaded sector into real memory",
"  setbpb               Fix BPB fields in loaded sector",
"  filebpb              Apply 'setbpb' to loaded file",
"  save                 Write adjusted sector back to disk",
"  hand                 Prepare handover area",
"  hptr                 Force ds:si and ds:bp to point to handover area",
"  swap                 Swap drive numbers, if bootdisk is not fd0/hd0",
"  nohide               Disable all hide variations (default)",
"  hide                 Hide primary partitions, unhide selected partition",
"  hideall              Hide *all* partitions, unhide selected partition",
"  unhide               Unhide primary partitions",
"  unhideall            Unhide *all* partitions",
"  fixchs               Walk *all* partitions and fix E/MBRs' CHS values",
"  keeppxe              Keep the PXE and UNDI stacks in memory (PXELINUX)",
"  warn                 Wait for a keypress to continue chainloading",
"  break                Don't chainload",
"  strict[=<0|1|2>]     Set the level of strictness in sanity checks",
"                       - strict w/o any value is the same as strict=2",
"  relax                The same as strict=0",
"  prefmbr              On hybrid MBR/GPT disks, prefer legacy layout",
"",
"  file=<file>          Load and execute <file>",
"  seg=<s[:o[:i]]>      Load file at <s:o>, jump to <s:i>",
"                       - defaults to 0:0x7C00:0x7C00",
"                       - omitted o/i values default to 0",
"  isolinux=<loader>    Load another version of ISOLINUX",
"  ntldr=<loader>       Load Windows NTLDR, SETUPLDR.BIN or BOOTMGR",
"  reactos=<loader>     Load ReactOS's loader",
"  cmldr=<loader>       Load Recovery Console of Windows NT/2K/XP/2003",
"  freedos=<loader>     Load FreeDOS KERNEL.SYS",
"  msdos=<loader>       Load MS-DOS 2.xx - 6.xx IO.SYS",
"  msdos7=<loader>      Load MS-DOS 7+ IO.SYS",
"  pcdos=<loader>       Load PC-DOS IBMBIO.COM",
"  drmk=<loader>        Load DRMK DELLBIO.BIN",
"  grub=<loader>        Load GRUB Legacy stage2",
"  grubcfg=<config>     Set alternative config filename for GRUB Legacy",
"  grldr=<loader>       Load GRUB4DOS grldr",
"  bss=<sectimage>      Emulate syslinux's BSS",
"  bs=<sectimage>       Emulate syslinux's BS",
"",
"Please see doc/chain.txt for the detailed documentation."
};
    for (i = 0; i < sizeof(usage)/sizeof(usage[0]); i++) {
	if (i % 20 == 19) {
	    puts("Press any key...");
	    wait_key();
	}
	puts(usage[i]);
    }
}

void opt_set_defs(void)
{
    memset(&opt, 0, sizeof opt);
    opt.sect = true;	    /* by def. load sector */
    opt.maps = true;	    /* by def. map sector */
    opt.hand = true;	    /* by def. prepare handover */
    opt.brkchain = false;   /* by def. do chainload */
    opt.piflags = PIF_STRICT;	/* by def. be strict, but ignore disk sizes */
    opt.foff = opt.soff = opt.fip = opt.sip = 0x7C00;
    opt.drivename = "boot";
#ifdef DEBUG
    opt.warn = true;
#endif
}

int opt_parse_args(int argc, char *argv[])
{
    int i;
    size_t v;
    char *p;

    for (i = 1; i < argc; i++) {
	if (!strncmp(argv[i], "file=", 5)) {
	    opt.file = argv[i] + 5;
	} else if (!strcmp(argv[i], "nofile")) {
	    opt.file = NULL;
	} else if (!strncmp(argv[i], "seg=", 4)) {
	    if (soi_s2n(argv[i] + 4, &opt.fseg, &opt.foff, &opt.fip, 0))
		goto bail;
	} else if (!strncmp(argv[i], "bss=", 4)) {
	    opt.file = argv[i] + 4;
	    opt.bss = true;
	    opt.maps = false;
	    opt.setbpb = true;
	} else if (!strncmp(argv[i], "bs=", 3)) {
	    opt.file = argv[i] + 3;
	    opt.sect = false;
	    opt.filebpb = true;
	} else if (!strncmp(argv[i], "isolinux=", 9)) {
	    opt.file = argv[i] + 9;
	    opt.isolinux = true;
	    opt.hand = false;
	    opt.sect = false;
	} else if (!strncmp(argv[i], "ntldr=", 6)) {
	    opt.fseg = 0x2000;  /* NTLDR wants this address */
	    opt.foff = 0;
	    opt.fip = 0;
	    opt.file = argv[i] + 6;
	    opt.setbpb = true;
	    opt.hand = false;
	} else if (!strncmp(argv[i], "reactos=", 8)) {
	    /*
	     * settings based on commit
	     *   ad4cf1470977f648ee1dd45e97939589ccb0393c
	     * note, conflicts with:
	     *   http://reactos.freedoors.org/Reactos%200.3.13/ReactOS-0.3.13-REL-src/boot/freeldr/notes.txt
	     */
	    opt.fseg = 0;
	    opt.foff = 0x8000;
	    opt.fip = 0x8100;
	    opt.file = argv[i] + 8;
	    opt.setbpb = true;
	    opt.hand = false;
	} else if (!strncmp(argv[i], "cmldr=", 6)) {
	    opt.fseg = 0x2000;  /* CMLDR wants this address */
	    opt.foff = 0;
	    opt.fip = 0;
	    opt.file = argv[i] + 6;
	    opt.cmldr = true;
	    opt.setbpb = true;
	    opt.hand = false;
	} else if (!strncmp(argv[i], "freedos=", 8)) {
	    opt.fseg = 0x60;    /* FREEDOS wants this address */
	    opt.foff = 0;
	    opt.fip = 0;
	    opt.sseg = 0x1FE0;
	    opt.file = argv[i] + 8;
	    opt.setbpb = true;
	    opt.hand = false;
	} else if ( (v = 6, !strncmp(argv[i], "msdos=", v) ||
		     !strncmp(argv[i], "pcdos=", v)) ||
		    (v = 7, !strncmp(argv[i], "msdos7=", v)) ) {
	    opt.fseg = 0x70;    /* MS-DOS 2.00 .. 6.xx wants this address */
	    opt.foff = 0;
	    opt.fip = v == 7 ? 0x200 : 0;  /* MS-DOS 7.0+ wants this ip */
	    opt.sseg = 0x8000;
	    opt.file = argv[i] + v;
	    opt.setbpb = true;
	    opt.hand = false;
	} else if (!strncmp(argv[i], "drmk=", 5)) {
	    opt.fseg = 0x70;    /* DRMK wants this address */
	    opt.foff = 0;
	    opt.fip = 0;
	    opt.sseg = 0x2000;
	    opt.soff = 0;
	    opt.sip = 0;
	    opt.file = argv[i] + 5;
	    /* opt.drmk = true; */
	    opt.setbpb = true;
	    opt.hand = false;
	} else if (!strncmp(argv[i], "grub=", 5)) {
	    opt.fseg = 0x800;	/* stage2 wants this address */
	    opt.foff = 0;
	    opt.fip = 0x200;
	    opt.file = argv[i] + 5;
	    opt.grub = true;
	    opt.hand = false;
	    opt.sect = false;
	} else if (!strncmp(argv[i], "grubcfg=", 8)) {
	    opt.grubcfg = argv[i] + 8;
	} else if (!strncmp(argv[i], "grldr=", 6)) {
	    opt.file = argv[i] + 6;
	    opt.grldr = true;
	    opt.hand = false;
	    opt.sect = false;
	} else if (!strcmp(argv[i], "keeppxe")) {
	    opt.keeppxe = 3;
	} else if (!strcmp(argv[i], "nokeeppxe")) {
	    opt.keeppxe = 0;
	} else if (!strcmp(argv[i], "maps")) {
	    opt.maps = true;
	} else if (!strcmp(argv[i], "nomaps")) {
	    opt.maps = false;
	} else if (!strcmp(argv[i], "hand")) {
	    opt.hand = true;
	} else if (!strcmp(argv[i], "nohand")) {
	    opt.hand = false;
	} else if (!strcmp(argv[i], "hptr")) {
	    opt.hptr = true;
	} else if (!strcmp(argv[i], "nohptr")) {
	    opt.hptr = false;
	} else if (!strcmp(argv[i], "swap")) {
	    opt.swap = true;
	} else if (!strcmp(argv[i], "noswap")) {
	    opt.swap = false;
	} else if (!strcmp(argv[i], "nohide")) {
	    opt.hide = HIDE_OFF;
	} else if (!strcmp(argv[i], "hide")) {
	    opt.hide = HIDE_ON;
	    opt.piflags |= PIF_STRICT | PIF_STRICTER;
	} else if (!strcmp(argv[i], "hideall")) {
	    opt.hide = HIDE_ON | HIDE_EXT;
	    opt.piflags |= PIF_STRICT | PIF_STRICTER;
	} else if (!strcmp(argv[i], "unhide")) {
	    opt.hide = HIDE_ON | HIDE_REV;
	    opt.piflags |= PIF_STRICT | PIF_STRICTER;
	} else if (!strcmp(argv[i], "unhideall")) {
	    opt.hide = HIDE_ON | HIDE_EXT | HIDE_REV;
	    opt.piflags |= PIF_STRICT | PIF_STRICTER;
	} else if (!strcmp(argv[i], "setbpb")) {
	    opt.setbpb = true;
	} else if (!strcmp(argv[i], "nosetbpb")) {
	    opt.setbpb = false;
	} else if (!strcmp(argv[i], "filebpb")) {
	    opt.filebpb = true;
	} else if (!strcmp(argv[i], "nofilebpb")) {
	    opt.filebpb = false;
	} else if (!strncmp(argv[i], "sect=", 5) ||
		   !strcmp(argv[i], "sect")) {
	    if (argv[i][4]) {
		if (soi_s2n(argv[i] + 5, &opt.sseg, &opt.soff, &opt.sip, 0))
		    goto bail;
	    }
	    opt.sect = true;
	} else if (!strcmp(argv[i], "nosect")) {
	    opt.sect = false;
	    opt.maps = false;
	} else if (!strcmp(argv[i], "save")) {
	    opt.save = true;
	    opt.piflags |= PIF_STRICT | PIF_STRICTER;
	} else if (!strcmp(argv[i], "nosave")) {
	    opt.save = false;
	} else if (!strcmp(argv[i], "fixchs")) {
	    opt.fixchs = true;
	    opt.piflags |= PIF_STRICT | PIF_STRICTER;
	} else if (!strcmp(argv[i], "nofixchs")) {
	    opt.fixchs = false;
	} else if (!strcmp(argv[i], "relax") || !strcmp(argv[i], "nostrict")) {
	    opt.piflags &= ~(PIF_STRICT | PIF_STRICTER);
	} else if (!strcmp(argv[i], "norelax") || !strcmp(argv[i], "strict")) {
	    opt.piflags |= PIF_STRICT | PIF_STRICTER;
	} else if (!strncmp(argv[i], "strict=", 7)) {
	    if (argv[i][7] < '0' || argv[i][7] > '2' || !argv[i][8]) {
		error("Strict level must be 0, 1 or 2.");
		goto bail;
	    }
	    opt.piflags &= ~(PIF_STRICT | PIF_STRICTER);
	    switch (argv[i][7]) {
		case '2': opt.piflags |= PIF_STRICTER;
		case '1': opt.piflags |= PIF_STRICT; break;
		default:;
	    }
	} else if (!strcmp(argv[i], "warn")) {
	    opt.warn = true;
	} else if (!strcmp(argv[i], "nowarn")) {
	    opt.warn = false;
	} else if (!strcmp(argv[i], "prefmbr")) {
	    opt.piflags |= PIF_PREFMBR;
	} else if (!strcmp(argv[i], "noprefmbr")) {
	    opt.piflags &= ~PIF_PREFMBR;
	} else if (!strcmp(argv[i], "nobreak")) {
	    opt.brkchain = false;
	} else if (!strcmp(argv[i], "break")) {
	    opt.brkchain = true;
	    opt.file = NULL;
	    opt.maps = false;
	    opt.hand = false;
	} else if (((argv[i][0] == 'h' || argv[i][0] == 'f')
		    && argv[i][1] == 'd')
		   || !strncmp(argv[i], "mbr:", 4)
		   || !strncmp(argv[i], "mbr=", 4)
		   || !strncmp(argv[i], "guid:", 5)
		   || !strncmp(argv[i], "guid=", 5)
		   || !strncmp(argv[i], "label:", 6)
		   || !strncmp(argv[i], "label=", 6)
		   || !strcmp(argv[i], "boot")
		   || !strncmp(argv[i], "boot,", 5)
		   || !strcmp(argv[i], "fs")) {
	    opt.drivename = argv[i];
	    if (strncmp(argv[i], "label", 5))
		p = strchr(opt.drivename, ',');
	    else
		p = NULL;
	    if (p) {
		*p = '\0';
		opt.partition = p + 1;
	    } else if (argv[i + 1] && argv[i + 1][0] >= '0'
		    && argv[i + 1][0] <= '9') {
		opt.partition = argv[++i];
	    }
	} else {
	    usage();
	    goto bail;
	}
    }

    if (opt.grubcfg && !opt.grub) {
	error("grubcfg=<filename> must be used together with grub=<loader>.");
	goto bail;
    }

    if (opt.filebpb && !opt.file) {
	error("Option 'filebpb' requires a file.");
	goto bail;
    }

    if (opt.save && !opt.sect) {
	error("Option 'save' requires a sector.");
	goto bail;
    }

    if (opt.setbpb && !opt.sect) {
	error("Option 'setbpb' requires a sector.");
	goto bail;
    }

    if (opt.maps && !opt.sect) {
	error("Option 'maps' requires a sector.");
	goto bail;
    }

    return 0;
bail:
    return -1;
}

/* vim: set ts=8 sts=4 sw=4 noet: */
