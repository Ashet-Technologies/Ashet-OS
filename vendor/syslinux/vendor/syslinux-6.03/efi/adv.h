#ifndef _H_EFI_ADV_
#define _H_EFI_ADV_

#include "efi.h"
#include "fio.h"
#include <syslinux/firmware.h>

/* ADV information */
#define ADV_SIZE	512	/* Total size */
#define ADV_LEN		(ADV_SIZE-3*4)	/* Usable data size */
#define SYSLINUX_FILE	"ldlinux.sys"

#define ADV_MAGIC1	0x5a2d2fa5	/* Head signature */
#define ADV_MAGIC2	0xa3041767	/* Total checksum */
#define ADV_MAGIC3	0xdd28bf64	/* Tail signature */

extern unsigned char syslinux_adv[2 * ADV_SIZE];
extern void *__syslinux_adv_ptr;
extern ssize_t __syslinux_adv_size;

/* TODO: Revisit to ensure if these functions need to be exported */
void syslinux_reset_adv(unsigned char *advbuf);
int syslinux_validate_adv(unsigned char *advbuf);
int read_adv(const char *path, const char *cfg);
int write_adv(const char *path, const char *cfg);

#endif
