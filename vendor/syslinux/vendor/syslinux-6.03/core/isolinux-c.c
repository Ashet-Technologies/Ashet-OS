#include <syslinux/config.h>
#include <com32.h>
#include <fs.h>

extern uint32_t OrigESDI;
extern const uint64_t Hidden;
extern uint16_t BIOSType;
extern uint16_t bios_cdrom;
extern uint8_t DriveNumber;
extern const void *spec_packet;

__export void get_derivative_info(union syslinux_derivative_info *di)
{
	di->iso.filesystem = SYSLINUX_FS_ISOLINUX;
	di->iso.sector_shift = SectorShift;
	di->iso.drive_number = DriveNumber;
	di->iso.cd_mode = ((BIOSType - bios_cdrom) >> 2);

	di->iso.spec_packet = &spec_packet;
	di->iso.esdi_ptr = &OrigESDI;
	di->iso.partoffset = &Hidden;
}
