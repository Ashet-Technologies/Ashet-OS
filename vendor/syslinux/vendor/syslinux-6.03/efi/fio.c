/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2007-2008 H. Peter Anvin - All Rights Reserved
 *   Copyright 2012 Intel Corporation; author: H. Peter Anvin
 *   Chandramouli Narayanan
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/* Miscellaneous functions for UEFI support
 * We assume that EFI library initialization has completed
 * and we have access to the global EFI exported variables
 *
 */
#include "efi.h"
#include "fio.h"

/* Variables that need to be exported
 * efi_errno - maintains the errors from EFI calls to display error messages.
 */
EFI_STATUS efi_errno = EFI_SUCCESS;

/* Locals
 * vol_root - handle to the root device for file operations
 */
static EFI_FILE_HANDLE vol_root;

/* Table of UEFI error messages to be indexed with the EFI errno
 * Update error message list as needed
 */
static CHAR16 *uefi_errmsg[] = {
	L"EFI_UNDEFINED",	/* should not get here */
	L"EFI_LOAD_ERROR",
	L"EFI_INVALID_PARAMETER",
	L"EFI_UNSUPPORTED",
	L"EFI_BAD_BUFFER_SIZE",
	L"EFI_BUFFER_TOO_SMALL",
	L"EFI_NOT_READY",
	L"EFI_DEVICE_ERROR",
	L"EFI_WRITE_PROTECTED",
	L"EFI_OUT_OF_RESOURCES",
	L"EFI_VOLUME_CORRUPTED",
	L"EFI_VOLUME_FULL",
	L"EFI_NO_MEDIA",
	L"EFI_MEDIA_CHANGED",
	L"EFI_NOT_FOUND",
	L"EFI_ACCESS_DENIED",
	L"EFI_NO_RESPONSE",
	L"EFI_NO_MAPPING",
	L"EFI_TIMEOUT",
	L"EFI_NOT_STARTED",
	L"EFI_ALREADY_STARTED",
	L"EFI_ABORTED",
	L"EFI_ICMP_ERROR",
	L"EFI_TFTP_ERROR",
	L"EFI_PROTOCOL_ERROR"
};

static UINTN nerrs = sizeof(uefi_errmsg)/sizeof(CHAR16 *);


/* Generic write error message; there is no gnu lib api to write to StdErr
 * For now, everything goes ConOut
 */
void efi_printerr(
    CHAR16   *fmt,
    ...
    )
{
    va_list     args;
    va_start (args, fmt);
    VPrint (fmt, args);
    va_end (args);
}

/* Simple console logger of efi-specific error messages. It uses
 * gnu-efi library Print function to do the job.
 */

void efi_perror(CHAR16 *prog)
{
	/* Ensure that the err number lies within range
	 * Beware: unsigned comparisons fail on efi, signed comparisons work
	 */
	if (EFI_ERROR(efi_errno) && (INTN)efi_errno < (INTN)nerrs)
		efi_printerr(L"%s: %s\n", prog, uefi_errmsg[efi_errno]);
}

/* Write to UEFI ConOut */
void efi_printout(
    CHAR16   *fmt,
    ...
    )
{
    va_list     args;
    va_start (args, fmt);
    VPrint (fmt, args);
    va_end (args);
}

/* IMPORTANT:
 * efi_setvol_root() needs to be called from efi main.
 * The rest of the ADV support relies on the file i/o environment
 * setup here. In order to use the EFI file support, we need
 * to set up the volume root. Subsequent file operations need the root to
 * access the interface routines.
 *
 */

EFI_STATUS efi_set_volroot(EFI_HANDLE device_handle)
{
	vol_root = LibOpenRoot(device_handle);
	if (!vol_root) {
		return EFI_DEVICE_ERROR;
	}
	return EFI_SUCCESS;
}

/* File operations using EFI runtime services */

/* Open the file using EFI runtime service
 * Opening a file in EFI requires a handle to the device
 * root in order to use the interface to the file operations supported by UEFI.
 * For now, assume device volume root handle from the loaded image
 *
 * Return a valid handle if open succeeded and null otherwise.
 * UEFI returns a bogus handle on error, so return null handle on error.
 *
 * TODO:
 * 1. Validate the assumption about the root device
 * 2. Can EFI open a file with full path name specification?
 * 3. Look into gnu-efi helper functions for dealing with device path/file path
 * 4. Consider utilizing EFI file open attributes.
 * 5. In EFI, file attributes can be specified only at the time of creation.
 * How do we support the equivalent of set_attributes() and clear_attributes()
 */
EFI_FILE_HANDLE efi_open(CHAR16 *file, UINT64 mode)
{
	/* initialize with NULL handle since EFI open returns bogus */
	EFI_FILE_HANDLE	fd = NULL;

	ASSERT(vol_root);

	/* Note that the attributes parameter is none for now */
	efi_errno = uefi_call_wrapper(vol_root->Open,
					5,
					vol_root,
					&fd,
					file,
					mode,
					0);
	return fd;
}

/*
 * read/write wrapper functions for UEFI
 *
 * Read or write the specified number of bytes starting at the
 * offset specified.
 *
 * Returns:
 * number of bytes read/written on success
 * -1 on error
 */
/* Wrapper function to read from a file */
size_t efi_xpread(EFI_FILE_HANDLE fd, void *buf, size_t count, off_t offset)
{
	ASSERT(fd);
	efi_errno = uefi_call_wrapper(fd->SetPosition,
					2,
				    fd,
				    offset);
	if (EFI_ERROR(efi_errno)) return -1;
	efi_errno = uefi_call_wrapper(fd->Read,
					3,
				    fd,
				    &count,
					buf);
	if (EFI_ERROR(efi_errno)) return -1;
	return count;
}

/* Wrapper function to write */
size_t efi_xpwrite(EFI_FILE_HANDLE fd, void *buf, size_t count, off_t offset)
{
	ASSERT(fd);
	efi_errno = uefi_call_wrapper(fd->SetPosition,
					2,
				    fd,
				    offset);
	if (EFI_ERROR(efi_errno)) return -1;
	efi_errno = uefi_call_wrapper(fd->Write,
					3,
				    fd,
				    &count,
					buf);
	if (EFI_ERROR(efi_errno)) return -1;
	return count;
}

/* For an open handle, return the generic file info excluding
 * the variable-length filename in the EFI_FILE_INFO structure.
 */
int efi_fstat(EFI_FILE_HANDLE fd, EFI_FILE_INFO *st)
{
	EFI_FILE_INFO *finfo;

	ASSERT(fd);
	finfo = LibFileInfo(fd);
	if (finfo) {
		uefi_call_wrapper(BS->CopyMem, 3, (VOID *)st, (VOID *)finfo, SIZE_OF_EFI_FILE_INFO);
		FreePool(finfo);
		return 0;
	}
	/* gnu-efi lib does not return EFI status; export a generic device error for now */
	efi_errno = EFI_DEVICE_ERROR;
	return -1;
}

/* set/clear_attributes()
 * 	Currently handles only VFAT filesystem
 * TODO:
 *    1. Assumes VFAT file system.
 *    2. How do we support other file systems?
 */
void efi_set_attributes(EFI_FILE_HANDLE fd)
{
	EFI_FILE_INFO *finfo;

	ASSERT(fd);
	finfo = LibFileInfo(fd);
	if (finfo) {
		/* Hidden+System+Readonly */
		finfo->Attribute = EFI_FILE_READ_ONLY|EFI_FILE_HIDDEN|EFI_FILE_SYSTEM;
		efi_errno = uefi_call_wrapper(fd->SetInfo,
					4,
					fd,
					&GenericFileInfo,
					finfo->Size,
					finfo);
		FreePool(finfo);
	} else efi_errno = EFI_NOT_FOUND;
}

void efi_clear_attributes(EFI_FILE_HANDLE fd)
{
	EFI_FILE_INFO *finfo;

	ASSERT(fd);
	finfo = LibFileInfo(fd);
	if (finfo) {
		finfo->Attribute = 0; /* no attributes */
		efi_errno = uefi_call_wrapper(fd->SetInfo, 
					4, 
					fd,
					&GenericFileInfo,
					finfo->Size,
					finfo);
		FreePool(finfo);
	} else efi_errno = EFI_NOT_FOUND;
}

/* Implement the sync operation using the EFI Flush file operation*/
void efi_sync(EFI_FILE_HANDLE fd)
{
	ASSERT(fd);
	efi_errno = uefi_call_wrapper(fd->Flush, 1, fd);
	return;
}

/* Close the file */
void efi_close(EFI_FILE_HANDLE fd)
{

	ASSERT(fd);
	efi_errno = uefi_call_wrapper(fd->Close, 1, fd);
	return;
}
