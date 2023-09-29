/* ----------------------------------------------------------------------- *
 *   
 *   Copyright 2010 Intel Corporation; author: H. Peter Anvin
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

/*
 * Based on:
 * 
 * 915 resolution by steve tomljenovic
 *
 * This was tested only on Sony VGN-FS550.  Use at your own risk
 *
 * This code is based on the techniques used in :
 *
 *   - 855patch.  Many thanks to Christian Zietz (czietz gmx net)
 *     for demonstrating how to shadow the VBIOS into system RAM
 *     and then modify it.
 *
 *   - 1280patch by Andrew Tipton (andrewtipton null li).
 *
 *   - 855resolution by Alain Poirier
 *
 * This source code is into the public domain.
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#define __USE_GNU
#include <string.h>
#include <sys/io.h>
#include <sys/cpu.h>
#include <sys/pci.h>
#include <unistd.h>
#include <assert.h>
#include <stdbool.h>
#include "video.h"
#include "debug.h"

#define VBIOS_START         0xc0000
#define VBIOS_SIZE          0x10000

#define MODE_TABLE_OFFSET_845G 617

#define VERSION "0.5.3"

#define ATI_SIGNATURE1 "ATI MOBILITY RADEON"
#define ATI_SIGNATURE2 "ATI Technologies Inc"
#define NVIDIA_SIGNATURE "NVIDIA Corp"
#define INTEL_SIGNATURE "Intel Corp"

typedef unsigned char * address;

typedef enum {
    CT_UNKWN, CT_830, CT_845G, CT_855GM, CT_865G, CT_915G, CT_915GM,
    CT_945G, CT_945GM, CT_946GZ, CT_G965, CT_Q965, CT_945GME,
    CHIPSET_TYPES
} chipset_type;

typedef enum {
    BT_UNKWN, BT_1, BT_2, BT_3
} bios_type;

static int freqs[] = { 60, 75, 85 };

typedef struct {
    uint8_t mode;
    uint8_t bits_per_pixel;
    uint16_t resolution;
    uint8_t unknown;
} __attribute__((packed)) vbios_mode;

typedef struct {
    uint16_t clock;		/* Clock frequency in 10 kHz */
    uint8_t x1;
    uint8_t x_total;
    uint8_t x2;
    uint8_t y1;
    uint8_t y_total;
    uint8_t y2;
} __attribute__((packed)) vbios_resolution_type1;

typedef struct {
    uint32_t clock;

    uint16_t x1;
    uint16_t htotal;
    uint16_t x2;
    uint16_t hblank;
    uint16_t hsyncstart;
    uint16_t hsyncend;

    uint16_t y1;
    uint16_t vtotal;
    uint16_t y2;
    uint16_t vblank;
    uint16_t vsyncstart;
    uint16_t vsyncend;
} __attribute__((packed)) vbios_modeline_type2;

typedef struct {
    uint8_t xchars;
    uint8_t ychars;
    uint8_t unknown[4];

    vbios_modeline_type2 modelines[];
} __attribute__((packed)) vbios_resolution_type2;

typedef struct {
    uint32_t clock;

    uint16_t x1;
    uint16_t htotal;
    uint16_t x2;
    uint16_t hblank;
    uint16_t hsyncstart;
    uint16_t hsyncend;

    uint16_t y1;
    uint16_t vtotal;
    uint16_t y2;
    uint16_t vblank;
    uint16_t vsyncstart;
    uint16_t vsyncend;

    uint16_t timing_h;
    uint16_t timing_v;

    uint8_t unknown[6];
} __attribute__((packed)) vbios_modeline_type3;

typedef struct {
    unsigned char unknown[6];

    vbios_modeline_type3 modelines[];
} __attribute__((packed)) vbios_resolution_type3;


typedef struct {
    unsigned int chipset_id;
    chipset_type chipset;
    bios_type bios;
    
    address bios_ptr;

    vbios_mode * mode_table;
    unsigned int mode_table_size;

    uint8_t b1, b2;

    bool unlocked;
} vbios_map;

#if 0				/* Debugging hacks */
static void good_marker(int x)
{
    ((uint16_t *)0xb8000)[x] = 0x2f30 - ((x & 0xf0) << 4) + (x & 0x0f);
}

static void bad_marker(int x)
{
    ((uint16_t *)0xb8000)[x] = 0x4f30 - ((x & 0xf0) << 4) + (x & 0x0f);
}

static void status(const char *fmt, ...)
{
    va_list ap;
    char msg[81], *p;
    int i;
    uint16_t *q;

    memset(msg, 0, sizeof msg);
    va_start(ap, fmt);
    vsnprintf(msg, sizeof msg, fmt, ap);
    va_end(ap);
    p = msg;
    q = (uint16_t *)0xb8000 + 80;
    for (i = 0; i < 80; i++)
	*q++ = *p++ + 0x1f00;
}
#else
static inline void good_marker(int x) { (void)x; }
static inline void bad_marker(int x) { (void)x; }
static inline void status(const char *fmt, ...) { (void)fmt; }
#endif

static unsigned int get_chipset_id(void) {
    return pci_readl(0x80000000);
}

static chipset_type get_chipset(unsigned int id) {
    chipset_type type;

    switch (id) {
    case 0x35758086:
        type = CT_830;
        break;

    case 0x25608086:
        type = CT_845G;
        break;
        
    case 0x35808086:
        type = CT_855GM;
        break;
        
    case 0x25708086:
        type = CT_865G;
        break;

    case 0x25808086:
	type = CT_915G;
	break;

    case 0x25908086:
        type = CT_915GM;
        break;

    case 0x27708086:
        type = CT_945G;
        break;

    case 0x27a08086:
        type = CT_945GM;
        break;

    case 0x29708086:
        type = CT_946GZ;
        break;

    case 0x29a08086:
	type = CT_G965;
	break;

    case 0x29908086:
        type = CT_Q965;
        break;

    case 0x27ac8086:
	type = CT_945GME;
	break;

    default:
        type = CT_UNKWN;
        break;
    }

    return type;
}


static vbios_resolution_type1 * map_type1_resolution(vbios_map * map,
						     uint16_t res)
{
    vbios_resolution_type1 * ptr = ((vbios_resolution_type1*)(map->bios_ptr + res)); 
    return ptr;
}

static vbios_resolution_type2 * map_type2_resolution(vbios_map * map,
						     uint16_t res)
{
    vbios_resolution_type2 * ptr = ((vbios_resolution_type2*)(map->bios_ptr + res)); 
    return ptr;
}

static vbios_resolution_type3 * map_type3_resolution(vbios_map * map,
						     uint16_t res)
{
    vbios_resolution_type3 * ptr = ((vbios_resolution_type3*)(map->bios_ptr + res)); 
    return ptr;
}


static bool detect_bios_type(vbios_map * map, int entry_size)
{
    unsigned int i;
    uint16_t r1, r2;
    
    r1 = r2 = 32000;

    for (i = 0; i < map->mode_table_size; i++) {
        if (map->mode_table[i].resolution <= r1) {
            r1 = map->mode_table[i].resolution;
    	} else if (map->mode_table[i].resolution <= r2) {
	    r2 = map->mode_table[i].resolution;
    	}
    }
    
    return ((r2-r1-6) % entry_size) == 0;
}

static inline void close_vbios(vbios_map *map)
{
    (void)map;
}

static vbios_map * open_vbios(void)
{
    static vbios_map _map;
    vbios_map * const map = &_map;

    memset(&_map, 0, sizeof _map);

    /*
     * Determine chipset
     */
    map->chipset_id = get_chipset_id();
    good_marker(0x10);
    map->chipset = get_chipset(map->chipset_id);
    good_marker(0x11);

    /*
     *  Map the video bios to memory
     */
    map->bios_ptr = (void *)VBIOS_START;

    /*
     * check if we have ATI Radeon
     */
    
    if (memmem(map->bios_ptr, VBIOS_SIZE, ATI_SIGNATURE1, strlen(ATI_SIGNATURE1)) ||
        memmem(map->bios_ptr, VBIOS_SIZE, ATI_SIGNATURE2, strlen(ATI_SIGNATURE2)) ) {
        debug("ATI chipset detected.  915resolution only works with Intel 800/900 series graphic chipsets.\r\n");
	return NULL;
    }

    /*
     * check if we have NVIDIA
     */
    
    if (memmem(map->bios_ptr, VBIOS_SIZE, NVIDIA_SIGNATURE, strlen(NVIDIA_SIGNATURE))) {
        debug("NVIDIA chipset detected.  915resolution only works with Intel 800/900 series graphic chipsets.\r\n");
	return NULL;
    }

    /*
     * check if we have Intel
     */
    
    if (map->chipset == CT_UNKWN && memmem(map->bios_ptr, VBIOS_SIZE, INTEL_SIGNATURE, strlen(INTEL_SIGNATURE))) {
        debug("Intel chipset detected.  However, 915resolution was unable to determine the chipset type.\r\n");

        debug("Chipset Id: %x\r\n", map->chipset_id);

        debug("Please report this problem to stomljen@yahoo.com\r\n");
        
        close_vbios(map);
	return NULL;
    }

    /*
     * check for others
     */

    if (map->chipset == CT_UNKWN) {
        debug("Unknown chipset type and unrecognized bios.\r\n");
        debug("915resolution only works with Intel 800/900 series graphic chipsets.\r\n");

        debug("Chipset Id: %x\r\n", map->chipset_id);
        close_vbios(map);
	return NULL;
    }

    /*
     * Figure out where the mode table is 
     */
    good_marker(0x12);

    {
        address p = map->bios_ptr + 16;
        address limit = map->bios_ptr + VBIOS_SIZE - (3 * sizeof(vbios_mode));
        
        while (p < limit && map->mode_table == 0) {
            vbios_mode * mode_ptr = (vbios_mode *) p;
            
            if (((mode_ptr[0].mode & 0xf0) == 0x30) && ((mode_ptr[1].mode & 0xf0) == 0x30) &&
                ((mode_ptr[2].mode & 0xf0) == 0x30) && ((mode_ptr[3].mode & 0xf0) == 0x30)) {

                map->mode_table = mode_ptr;
            }
            
            p++;
        }

        if (map->mode_table == 0) {
            debug("Unable to locate the mode table.\r\n");
            close_vbios(map);
	    return NULL;
        }
    }
    good_marker(0x13);

    /*
     * Determine size of mode table
     */
    
    {
        vbios_mode * mode_ptr = map->mode_table;
        
        while (mode_ptr->mode != 0xff) {
            map->mode_table_size++;
            mode_ptr++;
        }
    }
    good_marker(0x14);
    status("mode_table_size = %d", map->mode_table_size);

    /*
     * Figure out what type of bios we have
     *  order of detection is important
     */

    if (detect_bios_type(map, sizeof(vbios_modeline_type3))) {
        map->bios = BT_3;
    }
    else if (detect_bios_type(map, sizeof(vbios_modeline_type2))) {
        map->bios = BT_2;
    }
    else if (detect_bios_type(map, sizeof(vbios_resolution_type1))) {
        map->bios = BT_1;
    }
    else {
        debug("Unable to determine bios type.\r\n");
        debug("Mode Table Offset: $C0000 + $%x\r\n", ((unsigned int)map->mode_table) - ((unsigned int)map->bios_ptr));
        debug("Mode Table Entries: %u\r\n", map->mode_table_size);
	bad_marker(0x15);
	return NULL;
    }
    good_marker(0x15);

    return map;
}

static void unlock_vbios(vbios_map * map)
{
    assert(!map->unlocked);

    map->unlocked = true;
    
    switch (map->chipset) {
    case CT_UNKWN:
    case CHIPSET_TYPES:		/* Shut up gcc */
        break;
    case CT_830:
    case CT_855GM:
        map->b1 = pci_readb(0x8000005a);
        pci_writeb(0x33, 0x8000005a);
        break;
    case CT_845G:
    case CT_865G:
    case CT_915G:
    case CT_915GM:
    case CT_945G:
    case CT_945GM:
    case CT_945GME:
    case CT_946GZ:
    case CT_G965:
    case CT_Q965:
	map->b1 = pci_readb(0x80000091);
	map->b2 = pci_readb(0x80000092);
	pci_writeb(0x33, 0x80000091);
	pci_writeb(0x33, 0x80000092);
        break;
    }

#if DEBUG
    {
        unsigned int t = inl(0xcfc);
        debug("unlock PAM: (0x%08x)\r\n", t);
    }
#endif
}

static void relock_vbios(vbios_map * map)
{
    assert(map->unlocked);
    map->unlocked = false;
    
    switch (map->chipset) {
    case CT_UNKWN:
    case CHIPSET_TYPES:		/* Shut up gcc */
        break;
    case CT_830:
    case CT_855GM:
	pci_writeb(map->b1, 0x8000005a);
        break;
    case CT_845G:
    case CT_865G:
    case CT_915G:
    case CT_915GM:
    case CT_945G:
    case CT_945GM:
    case CT_945GME:
    case CT_946GZ:
    case CT_G965:
    case CT_Q965:
	pci_writeb(map->b1, 0x80000091);
	pci_writeb(map->b2, 0x80000092);
        break;
    }

#if DEBUG
    {
        unsigned int t = inl(0xcfc);
        debug("relock PAM: (0x%08x)\r\n", t);
    }
#endif
}

#if 0
static void list_modes(vbios_map *map, unsigned int raw)
{
    unsigned int i, x, y;

    for (i=0; i < map->mode_table_size; i++) {
        switch(map->bios) {
        case BT_1:
            {
                vbios_resolution_type1 * res = map_type1_resolution(map, map->mode_table[i].resolution);
                
                x = ((((unsigned int) res->x2) & 0xf0) << 4) | res->x1;
                y = ((((unsigned int) res->y2) & 0xf0) << 4) | res->y1;
                
                if (x != 0 && y != 0) {
                    debug("Mode %02x : %dx%d, %d bits/pixel\r\n", map->mode_table[i].mode, x, y, map->mode_table[i].bits_per_pixel);
                }

		if (raw)
		{
                    debug("Mode %02x (raw) :\r\n\t%02x %02x\r\n\t%02x\r\n\t%02x\r\n\t%02x\r\n\t%02x\r\n\t%02x\r\n\t%02x\r\n", map->mode_table[i].mode, res->unknow1[0],res->unknow1[1], res->x1,res->x_total,res->x2,res->y1,res->y_total,res->y2);
		}

            }
            break;
        case BT_2:
            {
                vbios_resolution_type2 * res = map_type2_resolution(map, map->mode_table[i].resolution);
                
                x = res->modelines[0].x1+1;
                y = res->modelines[0].y1+1;

                if (x != 0 && y != 0) {
                    debug("Mode %02x : %dx%d, %d bits/pixel\r\n", map->mode_table[i].mode, x, y, map->mode_table[i].bits_per_pixel);
                }
            }
            break;
        case BT_3:
            {
                vbios_resolution_type3 * res = map_type3_resolution(map, map->mode_table[i].resolution);
                
                x = res->modelines[0].x1+1;
                y = res->modelines[0].y1+1;
                
                if (x != 0 && y != 0) {
                    debug("Mode %02x : %dx%d, %d bits/pixel\r\n", map->mode_table[i].mode, x, y, map->mode_table[i].bits_per_pixel);
                }
            }
            break;
        case BT_UNKWN:
            break;
        }
    }
}
#endif

static void gtf_timings(int x, int y, int freq,	uint32_t *clock,
        uint16_t *hsyncstart, uint16_t *hsyncend, uint16_t *hblank,
        uint16_t *vsyncstart, uint16_t *vsyncend, uint16_t *vblank)
{
    int hbl, vbl, vfreq;

    vbl = y + (y+1)/(20000.0/(11*freq) - 1) + 1.5;
    vfreq = vbl * freq;
    hbl = 16 * (int)(x * (30.0 - 300000.0 / vfreq) /
            (70.0 + 300000.0 / vfreq) / 16.0 + 0.5);

    *vsyncstart = y;
    *vsyncend = y + 3;
    *vblank = vbl - 1;
    *hsyncstart = x + hbl / 2 - (x + hbl + 50) / 100 * 8 - 1;
    *hsyncend = x + hbl / 2 - 1;
    *hblank = x + hbl - 1;
    *clock = (x + hbl) * vfreq / 1000;
}

static int set_mode(vbios_map * map, unsigned int mode,
		     unsigned int x, unsigned int y, unsigned int bp,
		     unsigned int htotal, unsigned int vtotal)
{
    int xprev, yprev;
    unsigned int i, j;
    int rv = -1;

    for (i=0; i < map->mode_table_size; i++) {
        if (map->mode_table[i].mode == mode) {
            switch(map->bios) {
            case BT_1:
                {
                    vbios_resolution_type1 * res = map_type1_resolution(map, map->mode_table[i].resolution);
		    uint32_t clock;
		    uint16_t hsyncstart, hsyncend, hblank;
		    uint16_t vsyncstart, vsyncend, vblank;
                    
                    if (bp) {
                        map->mode_table[i].bits_per_pixel = bp;
                    }

		    gtf_timings(x, y, freqs[0], &clock,
				&hsyncstart, &hsyncend, &hblank,
				&vsyncstart, &vsyncend, &vblank);
		    
		    status("x = %d, y = %d, clock = %lu, h = %d %d %d, v = %d %d %d\n",
			  x, y, clock,
			  hsyncstart, hsyncend, hblank,
			  vsyncstart, vsyncend, vblank);

		    htotal = htotal ? htotal : (unsigned int)hblank+1;
		    vtotal = vtotal ? vtotal : (unsigned int)vblank+1;

		    res->clock = clock/10; /* Units appear to be 10 kHz */
                    res->x2 = (((htotal-x) >> 8) & 0x0f) | ((x >> 4) & 0xf0);
                    res->x1 = (x & 0xff);
                    
                    res->y2 = (((vtotal-y) >> 8) & 0x0f) | ((y >> 4) & 0xf0);
                    res->y1 = (y & 0xff);
		    if (htotal)
			res->x_total = ((htotal-x) & 0xff);

		    if (vtotal)
			res->y_total = ((vtotal-y) & 0xff);

		    rv = 0;
                }
                break;
            case BT_2:
                {
                    vbios_resolution_type2 * res = map_type2_resolution(map, map->mode_table[i].resolution);

                    res->xchars = x / 8;
                    res->ychars = y / 16 - 1;
                    xprev = res->modelines[0].x1;
                    yprev = res->modelines[0].y1;

                    for(j=0; j < 3; j++) {
                        vbios_modeline_type2 * modeline = &res->modelines[j];
                        
                        if (modeline->x1 == xprev && modeline->y1 == yprev) {
                            modeline->x1 = modeline->x2 = x-1;
                            modeline->y1 = modeline->y2 = y-1;

                            gtf_timings(x, y, freqs[j], &modeline->clock,
                                    &modeline->hsyncstart, &modeline->hsyncend,
                                    &modeline->hblank, &modeline->vsyncstart,
                                    &modeline->vsyncend, &modeline->vblank);

                            if (htotal)
                                modeline->htotal = htotal;
                            else
                                modeline->htotal = modeline->hblank;

                            if (vtotal)
                                modeline->vtotal = vtotal;
                            else
                                modeline->vtotal = modeline->vblank;
                        }
                    }

		    rv = 0;
                }
                break;
            case BT_3:
                {
                    vbios_resolution_type3 * res = map_type3_resolution(map, map->mode_table[i].resolution);
                    
                    xprev = res->modelines[0].x1;
                    yprev = res->modelines[0].y1;

                    for (j=0; j < 3; j++) {
                        vbios_modeline_type3 * modeline = &res->modelines[j];
                        
                        if (modeline->x1 == xprev && modeline->y1 == yprev) {
                            modeline->x1 = modeline->x2 = x-1;
                            modeline->y1 = modeline->y2 = y-1;
                            
                            gtf_timings(x, y, freqs[j], &modeline->clock,
                                    &modeline->hsyncstart, &modeline->hsyncend,
                                    &modeline->hblank, &modeline->vsyncstart,
                                    &modeline->vsyncend, &modeline->vblank);
                            if (htotal)
                                modeline->htotal = htotal;
                            else
                                modeline->htotal = modeline->hblank;
                            if (vtotal)
                                modeline->vtotal = vtotal;
                            else
                                modeline->vtotal = modeline->vblank;

                            modeline->timing_h   = y-1;
                            modeline->timing_v   = x-1;
                        }
                    }

		    rv = 0;
                }
                break;
            case BT_UNKWN:
                break;
            }
        }
    }

    return rv;
}   

static inline void display_map_info(vbios_map * map) {
#ifdef DEBUG
    static const char * bios_type_names[] =
	{"UNKNOWN", "TYPE 1", "TYPE 2", "TYPE 3"};
    static const char * chipset_type_names[] = {
	"UNKNOWN", "830", "845G", "855GM", "865G", "915G", "915GM", "945G",
	"945GM", "946GZ", "G965", "Q965", "945GME"
    };

    debug("Chipset: %s\r\n", chipset_type_names[map->chipset]);
    debug("BIOS: %s\r\n", bios_type_names[map->bios]);

    debug("Mode Table Offset: $C0000 + $%x\r\n",
	  ((unsigned int)map->mode_table) - ((unsigned int)map->bios_ptr));
    debug("Mode Table Entries: %u\r\n", map->mode_table_size);
#endif
    (void)map;
}

int __vesacon_i915resolution(int x, int y)
{
    vbios_map * map;
    unsigned int mode = 0x52;	/* 800x600x32 mode in known BIOSes */
    unsigned int bp = 32;	/* 32 bits per pixel */
    int rv = 0;

    good_marker(0);

    map = open_vbios();
    if (!map)
	return -1;

    good_marker(1);

    display_map_info(map);

    debug("\r\n");

    if (mode && x && y) {
	good_marker(2);
	cli();
	good_marker(3);
	unlock_vbios(map);
	good_marker(4);
        rv = set_mode(map, mode, x, y, bp, 0, 0);
	if (rv)
	    bad_marker(5);
	else
	    good_marker(5);
	relock_vbios(map);
	good_marker(6);
	sti();
        
        debug("Patch mode %02x to resolution %dx%d complete\r\n", mode, x, y);
    }
    close_vbios(map);
    
    return rv;
}
