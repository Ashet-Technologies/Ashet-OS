#include <sys/io.h>
#include <fs.h>
#include <com32.h>

#include "bios.h"
#include "graphics.h"
#include <syslinux/video.h>

/*
 * Write a single character in AL to the console without
 * mangling any registers; handle video pages correctly.
 */
__export void writechr(char data)
{
	com32sys_t ireg, oreg;

        memset(&ireg, 0, sizeof ireg);
        memset(&oreg, 0, sizeof oreg);
	write_serial(data);	/* write to serial port if needed */

	if (UsingVGA & 0x8)
		syslinux_force_text_mode();

	if (!(DisplayCon & 0x1))
		return;

	ireg.eax.b[0] = data;
	ireg.eax.b[1] = 0xE;
	ireg.ebx.b[0] = 0x07;	/* attribute */
	ireg.ebx.b[1] = *(uint8_t *)BIOS_page; /* current page */
	__intcall(0x10, &ireg, &oreg);
}

void pm_writechr(com32sys_t *regs)
{
	writechr(regs->eax.b[0]);
}
