/* ----------------------------------------------------------------------- *
 *
 *   Copyright 1999-2008 H. Peter Anvin - All Rights Reserved
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

#ifndef LIB_SYS_VESA_H
#define LIB_SYS_VESA_H

#include <syslinux/firmware.h>
#include <inttypes.h>
#include <com32.h>

/* VESA General Information table */
struct vesa_general_info {
    uint32_t signature;		/* Magic number = "VESA" */
    uint16_t version;
    far_ptr_t vendor_string;
    uint8_t capabilities[4];
    far_ptr_t video_mode_ptr;
    uint16_t total_memory;

    uint16_t oem_software_rev;
    far_ptr_t oem_vendor_name_ptr;
    far_ptr_t oem_product_name_ptr;
    far_ptr_t oem_product_rev_ptr;

    uint8_t reserved[222];
    uint8_t oem_data[256];
} __attribute__ ((packed));

#define VESA_MAGIC ('V' + ('E' << 8) + ('S' << 16) + ('A' << 24))
#define VBE2_MAGIC ('V' + ('B' << 8) + ('E' << 16) + ('2' << 24))

struct vesa_mode_info {
    uint16_t mode_attr;
    uint8_t win_attr[2];
    uint16_t win_grain;
    uint16_t win_size;
    uint16_t win_seg[2];
    far_ptr_t win_scheme;
    uint16_t logical_scan;

    uint16_t h_res;
    uint16_t v_res;
    uint8_t char_width;
    uint8_t char_height;
    uint8_t memory_planes;
    uint8_t bpp;
    uint8_t banks;
    uint8_t memory_layout;
    uint8_t bank_size;
    uint8_t image_pages;
    uint8_t page_function;

    uint8_t rmask;
    uint8_t rpos;
    uint8_t gmask;
    uint8_t gpos;
    uint8_t bmask;
    uint8_t bpos;
    uint8_t resv_mask;
    uint8_t resv_pos;
    uint8_t dcm_info;

    uint8_t *lfb_ptr;		/* Linear frame buffer address */
    uint8_t *offscreen_ptr;	/* Offscreen memory address */
    uint16_t offscreen_size;

    uint8_t reserved[206];
} __attribute__ ((packed));

struct vesa_info {
    struct vesa_general_info gi;
    struct vesa_mode_info mi;
};

extern struct vesa_info __vesa_info;

#if 0
static inline void vesa_debug(uint32_t color, int pos)
{
    uint32_t *stp = (uint32_t *) __vesa_info.mi.lfb_ptr;
    stp[pos * 3] = color;
}
#else
static inline void vesa_debug(uint32_t color, int pos)
{
    (void)color;
    (void)pos;
}
#endif

#endif /* LIB_SYS_VESA_H */
