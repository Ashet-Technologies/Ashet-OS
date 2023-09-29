/*
 * Copyright 2011-2014 Intel Corporation - All Rights Reserved
 */

#include <fs.h>
#include <ilog2.h>
#include <disk.h>
#include <dprintf.h>
#include "efi.h"

static inline EFI_STATUS read_blocks(EFI_BLOCK_IO *bio, uint32_t id, 
				     sector_t lba, UINTN bytes, void *buf)
{
	return uefi_call_wrapper(bio->ReadBlocks, 5, bio, id, lba, bytes, buf);
}

static inline EFI_STATUS write_blocks(EFI_BLOCK_IO *bio, uint32_t id, 
				     sector_t lba, UINTN bytes, void *buf)
{
	return uefi_call_wrapper(bio->WriteBlocks, 5, bio, id, lba, bytes, buf);
}

static int efi_rdwr_sectors(struct disk *disk, void *buf,
			    sector_t lba, size_t count, bool is_write)
{
	struct efi_disk_private *priv = (struct efi_disk_private *)disk->private;
	EFI_BLOCK_IO *bio = priv->bio;
	EFI_STATUS status;
	UINTN bytes = count * disk->sector_size;

	if (is_write)
		status = write_blocks(bio, disk->disk_number, lba, bytes, buf);
	else
		status = read_blocks(bio, disk->disk_number, lba, bytes, buf);

	if (status != EFI_SUCCESS)
		Print(L"Failed to %s blocks: 0x%x\n",
			is_write ? L"write" : L"read",
			status);

	return count << disk->sector_shift;
}

struct disk *efi_disk_init(void *private)
{
    static struct disk disk;
    struct efi_disk_private *priv = (struct efi_disk_private *)private;
    EFI_HANDLE handle = priv->dev_handle;
    EFI_BLOCK_IO *bio;
    EFI_DISK_IO *dio;
    EFI_STATUS status;

    status = uefi_call_wrapper(BS->HandleProtocol, 3, handle,
			       &DiskIoProtocol, (void **)&dio);
    if (status != EFI_SUCCESS)
	    return NULL;

    status = uefi_call_wrapper(BS->HandleProtocol, 3, handle,
			       &BlockIoProtocol, (void **)&bio);
    if (status != EFI_SUCCESS)
	    return NULL;

    /*
     * XXX Do we need to map this to a BIOS disk number?
     */
    disk.disk_number   = bio->Media->MediaId;

    disk.sector_size   = bio->Media->BlockSize;
    disk.rdwr_sectors  = efi_rdwr_sectors;
    disk.sector_shift  = ilog2(disk.sector_size);

    dprintf("sector_size=%d, disk_number=%d\n", disk.sector_size,
	    disk.disk_number);

    priv->bio = bio;
    priv->dio = dio;
    disk.private = private;
#if 0

    disk.part_start    = part_start;
    disk.secpercyl     = disk.h * disk.s;


    disk.maxtransfer   = MaxTransfer;

    dprintf("disk %02x cdrom %d type %d sector %u/%u offset %llu limit %u\n",
	    media_id, cdrom, ebios, sector_size, disk.sector_shift,
	    part_start, disk.maxtransfer);
#endif

    return &disk;
}
