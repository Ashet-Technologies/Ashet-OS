/*
 * Copyright 2011-2014 Intel Corporation - All Rights Reserved
 */

#include <syslinux/linux.h>
#include "efi.h"
#include <string.h>

extern EFI_GUID GraphicsOutputProtocol;

static uint32_t console_default_attribute;
static bool console_default_cursor;

/*
 * We want to restore the console state when we boot a kernel or return
 * to the firmware.
 */
void efi_console_save(void)
{
    SIMPLE_TEXT_OUTPUT_INTERFACE *out = ST->ConOut;
    SIMPLE_TEXT_OUTPUT_MODE *mode = out->Mode;

    console_default_attribute = mode->Attribute;
    console_default_cursor = mode->CursorVisible;
}

void efi_console_restore(void)
{
    SIMPLE_TEXT_OUTPUT_INTERFACE *out = ST->ConOut;

    uefi_call_wrapper(out->SetAttribute, 2, out, console_default_attribute);
    uefi_call_wrapper(out->EnableCursor, 2, out, console_default_cursor);
}

__export void writechr(char data)
{
	efi_write_char(data, 0);
}

static inline EFI_STATUS open_protocol(EFI_HANDLE handle, EFI_GUID *protocol,
				       void **interface, EFI_HANDLE agent,
				       EFI_HANDLE controller, UINT32 attributes)
{
	return uefi_call_wrapper(BS->OpenProtocol, 6, handle, protocol,
				 interface, agent, controller, attributes);
}

static inline EFI_STATUS
gop_query_mode(EFI_GRAPHICS_OUTPUT_PROTOCOL *gop, UINTN *size,
	       EFI_GRAPHICS_OUTPUT_MODE_INFORMATION **info)
{
	return uefi_call_wrapper(gop->QueryMode, 4, gop,
				 gop->Mode->Mode, size, info);
}

static inline void bit_mask(uint32_t mask, uint8_t *pos, uint8_t *size)
{
	*pos = 0;
	*size = 0;

	if (mask) {
		while (!(mask & 0x1)) {
			mask >>= 1;
			(*pos)++;
		}

		while (mask & 0x1) {
			mask >>= 1;
			(*size)++;
		}
	}
}

static int setup_gop(struct screen_info *si)
{
	EFI_HANDLE *handles = NULL;
	EFI_STATUS status;
	EFI_GRAPHICS_OUTPUT_PROTOCOL *gop, *found;
	EFI_GRAPHICS_PIXEL_FORMAT pixel_fmt;
	EFI_PIXEL_BITMASK pixel_info;
	uint32_t pixel_scanline;
	UINTN i, nr_handles;
	UINTN size;
	uint16_t lfb_width, lfb_height;
	uint32_t lfb_base, lfb_size;
	int err = 0;
	void **gop_handle = NULL;

	size = 0;
	status = uefi_call_wrapper(BS->LocateHandle, 5, ByProtocol, &GraphicsOutputProtocol,
				NULL, &size, gop_handle);
	/* LibLocateHandle handle already returns the number of handles.
	 * There is no need to divide by sizeof(EFI_HANDLE)
	 */
	status = LibLocateHandle(ByProtocol, &GraphicsOutputProtocol,
				 NULL, &nr_handles, &handles);
	if (status == EFI_BUFFER_TOO_SMALL) {

		handles = AllocatePool(nr_handles);
		if (!handles)
			return 0;

		status = LibLocateHandle(ByProtocol, &GraphicsOutputProtocol,
					 NULL, &nr_handles, &handles);
	}
	if (status != EFI_SUCCESS)
		goto out;

	found = NULL;
	for (i = 0; i < nr_handles; i++) {
		EFI_GRAPHICS_OUTPUT_MODE_INFORMATION *info;
		EFI_PCI_IO *pciio = NULL;
		EFI_HANDLE *h = handles[i];

		status = uefi_call_wrapper(BS->HandleProtocol, 3, h,
					   &GraphicsOutputProtocol, (void **)&gop);
		if (status != EFI_SUCCESS)
			continue;
		uefi_call_wrapper(BS->HandleProtocol, 3, h,
				  &PciIoProtocol, (void **)&pciio);
		status = gop_query_mode(gop, &size, &info);
		if (status == EFI_SUCCESS && (!found || pciio)) {
			lfb_width = info->HorizontalResolution;
			lfb_height = info->VerticalResolution;
			lfb_base = gop->Mode->FrameBufferBase;
			lfb_size = gop->Mode->FrameBufferSize;
			pixel_fmt = info->PixelFormat;
			pixel_info = info->PixelInformation;
			pixel_scanline = info->PixelsPerScanLine;
			if (pciio)
				break;
			found = gop;
		}
	}

	if (!found)
		goto out;

	err = 1;

	dprintf("setup_screen: set up screen parameters for EFI GOP\n");
	si->orig_video_isVGA = 0x70; /* EFI framebuffer */

	si->lfb_base = lfb_base;
	si->lfb_size = lfb_size;
	si->lfb_width = lfb_width;
	si->lfb_height = lfb_height;
	si->pages = 1;

	dprintf("setup_screen: lfb_base 0x%x lfb_size %d lfb_width %d lfb_height %d\n", lfb_base, lfb_size, lfb_width, lfb_height);
	switch (pixel_fmt) {
	case PixelRedGreenBlueReserved8BitPerColor:
		si->lfb_depth = 32;
		si->lfb_linelength = pixel_scanline * 4;
		si->red_size = 8;
		si->red_pos = 0;
		si->green_size = 8;
		si->green_pos = 8;
		si->blue_size = 8;
		si->blue_pos = 16;
		si->rsvd_size = 8;
		si->rsvd_pos = 24;
		break;
	case PixelBlueGreenRedReserved8BitPerColor:
		si->lfb_depth = 32;
		si->lfb_linelength = pixel_scanline * 4;
		si->red_size = 8;
		si->red_pos = 16;
		si->green_size = 8;
		si->green_pos = 8;
		si->blue_size = 8;
		si->blue_pos = 0;
		si->rsvd_size = 8;
		si->rsvd_pos = 24;
		break;
	case PixelBitMask:
		bit_mask(pixel_info.RedMask, &si->red_pos,
			 &si->red_size);
		bit_mask(pixel_info.GreenMask, &si->green_pos,
			 &si->green_size);
		bit_mask(pixel_info.BlueMask, &si->blue_pos,
			 &si->blue_size);
		bit_mask(pixel_info.ReservedMask, &si->rsvd_pos,
			 &si->rsvd_size);
		si->lfb_depth = si->red_size + si->green_size +
			si->blue_size + si->rsvd_size;
		si->lfb_linelength = (pixel_scanline * si->lfb_depth) / 8;
		break;
	default:
		si->lfb_depth = 4;;
		si->lfb_linelength = si->lfb_width / 2;
		si->red_size = 0;
		si->red_pos = 0;
		si->green_size = 0;
		si->green_pos = 0;
		si->blue_size = 0;
		si->blue_pos = 0;
		si->rsvd_size = 0;
		si->rsvd_pos = 0;
		break;
	}
	dprintf("setup_screen: depth %d line %d rpos %d rsize %d gpos %d gsize %d bpos %d bsize %d rsvpos %d rsvsize %d\n",
		si->lfb_depth, si->lfb_linelength,
		si->red_pos, si->red_size,
		si->green_pos, si->green_size,
		si->blue_pos, si->blue_size,
		si->blue_pos, si->blue_size,
		si->rsvd_pos, si->rsvd_size);
	
out:
	if (handles) FreePool(handles);

	return err;
}

#define EFI_UGA_PROTOCOL_GUID \
  { \
    0x982c298b, 0xf4fa, 0x41cb, {0xb8, 0x38, 0x77, 0xaa, 0x68, 0x8f, 0xb8, 0x39 } \
  }

typedef struct _EFI_UGA_DRAW_PROTOCOL EFI_UGA_DRAW_PROTOCOL;

typedef
EFI_STATUS
(EFIAPI *EFI_UGA_DRAW_PROTOCOL_GET_MODE) (
  IN  EFI_UGA_DRAW_PROTOCOL *This,
  OUT UINT32 *Width,
  OUT UINT32 *Height,
  OUT UINT32 *Depth,
  OUT UINT32 *Refresh
  )
;

struct _EFI_UGA_DRAW_PROTOCOL {
	EFI_UGA_DRAW_PROTOCOL_GET_MODE	GetMode;
	void	*SetMode;
	void	*Blt;
};

static int setup_uga(struct screen_info *si)
{
	EFI_UGA_DRAW_PROTOCOL *uga, *first;
	EFI_GUID UgaProtocol = EFI_UGA_PROTOCOL_GUID;
	UINT32 width, height;
	EFI_STATUS status;
	EFI_HANDLE *handles;
	UINTN i, nr_handles;
	int rv = 0;

	status = LibLocateHandle(ByProtocol, &UgaProtocol,
				 NULL, &nr_handles, &handles);
	if (status != EFI_SUCCESS)
		return rv;

	for (i = 0; i < nr_handles; i++) {
		EFI_PCI_IO *pciio = NULL;
		EFI_HANDLE *handle = handles[i];
		UINT32 w, h, depth, refresh;

		status = uefi_call_wrapper(BS->HandleProtocol, 3, handle,
					   &UgaProtocol, (void **)&uga);
		if (status != EFI_SUCCESS)
			continue;

		uefi_call_wrapper(BS->HandleProtocol, 3, handle,
				  &PciIoProtocol, (void **)&pciio);

		status = uefi_call_wrapper(uga->GetMode, 5, uga, &w, &h,
					   &depth, &refresh);

		if (status == EFI_SUCCESS && (!first || pciio)) {
			width = w;
			height = h;

			if (pciio)
				break;

			first = uga;
		}
	}

	if (!first)
		goto out;
	rv = 1;

	si->orig_video_isVGA = 0x70; /* EFI framebuffer */

	si->lfb_depth = 32;
	si->lfb_width = width;
	si->lfb_height = height;

	si->red_size = 8;
	si->red_pos = 16;
	si->green_size = 8;
	si->green_pos = 8;
	si->blue_size = 8;
	si->blue_pos = 0;
	si->rsvd_size = 8;
	si->rsvd_pos = 24;

out:
	FreePool(handles);
	return rv;
}

void setup_screen(struct screen_info *si)
{
	memset(si, 0, sizeof(*si));

	if (!setup_gop(si))
		setup_uga(si);
}
