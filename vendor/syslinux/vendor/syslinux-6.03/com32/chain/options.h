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

#ifndef COM32_CHAIN_OPTIONS_H
#define COM32_CHAIN_OPTIONS_H

#include <stdint.h>
#include <syslinux/bootrm.h>
#include <syslinux/movebits.h>

enum {HIDE_OFF = 0, HIDE_ON = 1, HIDE_EXT = 2, HIDE_REV = 4};

struct options {
    const char *drivename;
    const char *partition;
    const char *file;
    const char *grubcfg;
    addr_t fseg;
    addr_t foff;
    addr_t fip;
    addr_t sseg;
    addr_t soff;
    addr_t sip;
    int hide;
    int piflags;
    uint16_t keeppxe;
    bool isolinux;
    bool cmldr;
    bool drmk;
    bool grub;
    bool grldr;
    bool maps;
    bool hand;
    bool hptr;
    bool swap;
    bool sect;
    bool save;
    bool bss;
    bool setbpb;
    bool filebpb;
    bool fixchs;
    bool warn;
    bool brkchain;
    struct syslinux_rm_regs regs;
};

extern struct options opt;

void opt_set_defs(void);
int opt_parse_args(int argc, char *argv[]);

#endif

/* vim: set ts=8 sts=4 sw=4 noet: */
