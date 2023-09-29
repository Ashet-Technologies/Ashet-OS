#include <syslinux/config.h>
#include <com32.h>
#include <fs.h>

extern uint8_t DriveNumber;
extern void *PartInfo;
extern uint32_t OrigESDI;
extern const uint64_t Hidden;

__export void get_derivative_info(union syslinux_derivative_info *di)
{
	di->disk.filesystem = SYSLINUX_FS_SYSLINUX;
	di->disk.sector_shift = SectorShift;
	di->disk.drive_number = DriveNumber;

	di->disk.ptab_ptr = &PartInfo;
	di->disk.esdi_ptr = &OrigESDI;
	di->disk.partoffset = &Hidden;
}
