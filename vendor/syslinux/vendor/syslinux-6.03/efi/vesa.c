/* ----------------------------------------------------------------------- *
 *
 *   Copyright 1999-2012 H. Peter Anvin - All Rights Reserved
 *   Chandramouli Narayanan - extended for EFI support
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

#include <inttypes.h>
#include <com32.h>
#include <stdlib.h>
#include <string.h>
#include <sys/fpu.h>
#include <syslinux/video.h>
#include <dprintf.h>
#include "efi.h"
/* We use cp865_8x16.psf as the standard font for EFI implementation
 * the header file below contains raw data parsed from cp865_8x16.psf
 */
#include "cp865_8x16.h"
#include "sys/vesa/vesa.h"
#include "sys/vesa/video.h"
#include "sys/vesa/fill.h"
#include "sys/vesa/debug.h"

/* EFI GOP support
 * Note GOP support uses the VESA info structure as much as possible and
 * extends it as needed for EFI support. Not all of the vesa info structure
 * is populated. Care must be taken in the routines that rely the vesa
 * informataion structure
 */
static void find_pixmask_bits(uint32_t mask, uint8_t *first_bit, uint8_t *len) {
    uint8_t bit_pos = 0, bit_len = 0;

    *first_bit = 0;
    *len = 0;
    if (mask == 0)
	return;
    while (!(mask & 0x1)) {
	mask = mask >> 1;
	bit_pos++;
    }
    while (mask & 0x1) {
	mask = mask >> 1;
	bit_len++;
    }
    *first_bit = bit_pos;
    *len = bit_len;
}

unsigned long lfb_size;
uint16_t lfb_line_size;
uint8_t lfb_rsize;
uint8_t lfb_gsize;
uint8_t lfb_bsize;
uint8_t lfb_resv_size;

static int efi_vesacon_set_mode(struct vesa_info *vesa_info, int *x, int *y,
				enum vesa_pixel_format *bestpxf)
{
    EFI_GUID GraphicsOutputProtocolGuid = EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID;
    EFI_GRAPHICS_OUTPUT_PROTOCOL *GraphicsOutput = NULL;
    EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE *gop_mode;
    EFI_GRAPHICS_OUTPUT_MODE_INFORMATION *mode_info;
    EFI_STATUS st;
    UINT32 mode_num = 0, bestmode;
    BOOLEAN mode_match = FALSE;
    UINTN sz_info;
    struct vesa_info *vi;
    struct vesa_mode_info *mi;
    int err = 0;

    //debug("Hello, World!\r\n");
    /* At this point, we assume that gnu-efi library is initialized */
    st = LibLocateProtocol(&GraphicsOutputProtocolGuid, (VOID **) &GraphicsOutput);
    if (EFI_ERROR(st)) {
	debug("LiblocateProtocol for GOP failed %d\n", st);
	return 1; /* function call failed */
    }

    /* We use the VESA info structure to store relevant GOP info as much as possible */
    gop_mode = GraphicsOutput->Mode;

    mode_info = gop_mode->Info;
    dprintf("mode %d version %d pixlfmt %d hres=%d vres=%d\n", mode_num, 
			mode_info->Version, mode_info->PixelFormat,
			mode_info->HorizontalResolution, mode_info->VerticalResolution);
    
    /* simply pick the best mode that suits the caller's resolution */
    for (mode_num = 0; mode_num < gop_mode->MaxMode; mode_num++) {
	st = uefi_call_wrapper(GraphicsOutput->QueryMode, 4, GraphicsOutput, mode_num, &sz_info, &mode_info);
	debug("mode_num = %d query_status %d\n", mode_num, st);
	if (st == EFI_SUCCESS && sz_info >= sizeof(EFI_GRAPHICS_OUTPUT_MODE_INFORMATION)) {

		/* For now, simply pick the best mode that suits caller's resolution (x,y)
		 * FIXME: Consider any additional criteria for matching mode
		 */
		mode_match = ((uint32_t)*x == mode_info->HorizontalResolution && (uint32_t)*y == mode_info->VerticalResolution);
		debug("mode %d hres=%d vres=%d\n", mode_num, mode_info->HorizontalResolution, mode_info->VerticalResolution);
		if (mode_match) {
			bestmode = mode_num;
			break;
		}
	}
    }

    if (!mode_match) {
	/* Instead of bailing out, set the mode to the system default.
 	 * Some systems do not have support for 640x480 for instance
 	 * This code deals with such cases.
 	 */
	mode_info = gop_mode->Info;
	*x = mode_info->HorizontalResolution;
	*y = mode_info->VerticalResolution;
	bestmode = gop_mode->Mode;
	debug("No matching mode, setting to available default mode %d (x=%d, y=%d)\n", bestmode, *x, *y);
    }

    /* Allocate space in the bounce buffer for these structures */
    vi = malloc(sizeof(*vi));
    if (!vi) {
	err = 10;		/* Out of memory */
	goto exit;
    }
    /* Note that the generic info is untouched as we don't find any relevance to EFI */
    mi = &vi->mi;
    /* Set up mode-specific information */
    mi->h_res = *x;
    mi->v_res = *y;
    mi->lfb_ptr = (uint8_t *)(VOID *)(UINTN)gop_mode->FrameBufferBase;
    lfb_size = gop_mode->FrameBufferSize;

    /* FIXME: 
     * The code below treats bpp == lfb_depth ; verify
     */

    switch (mode_info->PixelFormat) {
    case PixelRedGreenBlueReserved8BitPerColor:
	dprintf("RGB8bit ");
	mi->mode_attr = 0x0080;		/* supports physical frame buffer */
	mi->bpp = sizeof(EFI_GRAPHICS_OUTPUT_BLT_PIXEL) * 8;
	mi->rpos = 0;
	mi->gpos = 8;
	mi->bpos = 16;
	mi->resv_pos = 24;
	lfb_resv_size = 8;
	mi->logical_scan = lfb_line_size = (mode_info->PixelsPerScanLine * mi->bpp) / 8;
	*bestpxf = PXF_BGRA32;
	dprintf("bpp %d pixperScanLine %d logical_scan %d bytesperPix %d\n", mi->bpp, mode_info->PixelsPerScanLine, 
		mi->logical_scan, (mi->bpp + 7)>>3);
	break;
    case PixelBlueGreenRedReserved8BitPerColor:
	dprintf("BGR8bit ");
	mi->mode_attr = 0x0080;		/* supports physical frame buffer */
	mi->bpp = sizeof(EFI_GRAPHICS_OUTPUT_BLT_PIXEL) * 8;
	mi->bpos = 0;
	mi->gpos = 8;
	mi->rpos = 16;
	mi->resv_pos = 24;
	lfb_resv_size = 8;
	mi->logical_scan = lfb_line_size = (mode_info->PixelsPerScanLine * mi->bpp) / 8;
	*bestpxf = PXF_BGRA32;
	dprintf("bpp %d pixperScanLine %d logical_scan %d bytesperPix %d\n", mi->bpp, mode_info->PixelsPerScanLine, 
		mi->logical_scan, (mi->bpp + 7)>>3);
	break;
    case PixelBitMask:
	mi->mode_attr = 0x0080;		/* supports physical frame buffer */
	dprintf("RedMask 0x%x GrnMask 0x%x BluMask 0x%x RsvMask 0x%x\n",
		mode_info->PixelInformation.RedMask,
		mode_info->PixelInformation.GreenMask,
		mode_info->PixelInformation.BlueMask,
		mode_info->PixelInformation.ReservedMask);
	find_pixmask_bits(mode_info->PixelInformation.RedMask,
                          &mi->rpos, &lfb_rsize);
	find_pixmask_bits(mode_info->PixelInformation.GreenMask,
                          &mi->gpos, &lfb_gsize);
	find_pixmask_bits(mode_info->PixelInformation.BlueMask,
                          &mi->bpos, &lfb_bsize);
	find_pixmask_bits(mode_info->PixelInformation.ReservedMask,
                          &mi->resv_pos, &lfb_resv_size);
	mi->bpp = lfb_rsize + lfb_gsize +
                                  lfb_bsize + lfb_resv_size;
	mi->logical_scan = lfb_line_size = (mode_info->PixelsPerScanLine * mi->bpp) / 8;
	dprintf("RPos %d Rsize %d GPos %d Gsize %d\n", mi->rpos, lfb_rsize, mi->gpos, lfb_gsize);
	dprintf("BPos %d Bsize %d RsvP %d RsvSz %d\n", mi->bpos, lfb_bsize, mi->resv_pos, lfb_resv_size);
	dprintf("bpp %d logical_scan %d bytesperPix %d\n", mi->bpp, mi->logical_scan, (mi->bpp + 7)>>3);
	switch (mi->bpp) {
	case 32:
		*bestpxf = PXF_BGRA32;
		break;
	case 24:
		*bestpxf = PXF_BGR24;
		break;
	case 16:
		*bestpxf = PXF_LE_RGB16_565;
		break;
	default:
		dprintf("Unable to handle bits per pixel %d, bailing out\n", mi->bpp);
		err = 4;
		goto exit;
	}
	break;
    case PixelBltOnly:
	/* FIXME: unsupported */
	mi->mode_attr = 0x0000;		/* no support for physical frame buffer */
	err = 4; /* no mode found */
	goto exit;
	break;
    default:
	/* should not get here, but let's error out */
	err = 4; /* no mode found */
	goto exit;
	break;
    }		   
    
    memcpy(&vesa_info->mi, mi, sizeof *mi);

    /* Now set video mode */
    st = uefi_call_wrapper(GraphicsOutput->SetMode, 2, GraphicsOutput, bestmode);
    if (EFI_ERROR(st)) {
	err = 9;		/* Failed to set mode */
	dprintf("Failed to set mode %d\n", bestmode);
	goto exit;
    }	

    /* TODO: Follow the code usage of vesacon_background & vesacon_shadowfb */
    /*
     __vesacon_background = calloc(mi->h_res*mi->v_res, 4);
     __vesacon_shadowfb = calloc(mi->h_res*mi->v_res, 4);
     */
     /* FIXME: the allocation takes the possible padding into account
      * whereas   BIOS code simply allocates hres * vres bytes.
      * Which is correct?
      */
     /*
      * For performance reasons, or due to hardware restrictions, scan lines
      * may be padded to an amount of memory alignment. These padding pixel elements
      * are outside the area covered by HorizontalResolution and are not visible.
      * For direct frame buffer access, this number is used as a span between starts
      * of pixel lines in video memory. Based on the size of an individual pixel element
      * and PixelsPerScanline, the offset in video memory from pixel element (x, y)
      * to pixel element (x, y+1) has to be calculated as 
      * "sizeof( PixelElement ) * PixelsPerScanLine", and not 
      * "sizeof( PixelElement ) * HorizontalResolution", though in many cases
      * those values can coincide.
      */

exit:
    if (vi)
	free(vi);

    return err;
}

static void efi_vesacon_screencpy(size_t dst, const uint32_t *s,
				  size_t bytes, struct win_info *wi)
{
    size_t win_off;
    char *win_base = wi->win_base;
 
    /* For EFI, we simply take the offset from the framebuffer and write to it
     * FIXME: any gotchas?
     */
    win_off = dst;
    memcpy(win_base + win_off, s, bytes);
}

static int efi_vesacon_font_query(uint8_t **font)
{
    /* set up font info
     * For now, font info is stored as raw data and used
     * as such. Altenatively, the font data stored in a file 
     * could be read and parsed. (note: for this, EFI
     * file support should be exposed via firmware structure)
     */
    *font = (uint8_t *)cp865_8x16_font_data;
    return cp865_8x16_font_height;
}

__export int __vesacon_i915resolution(int x, int y)
{
	/* We don't support this function */
	return 1;
}

struct vesa_ops efi_vesa_ops = {
	.set_mode = efi_vesacon_set_mode,
	.screencpy = efi_vesacon_screencpy,
	.font_query = efi_vesacon_font_query,
};
