/*
 * writechr:	Write a single character in AL to the console without
 *		mangling any registers.  This does raw console writes,
 *		since some PXE BIOSes seem to interfere regular console I/O.
 */
#include <sys/io.h>
#include <fs.h>
#include <com32.h>

#include "bios.h"
#include "graphics.h"
#include <syslinux/video.h>

__export void writechr(char data)
{
	if (UsingVGA & 0x08)
		syslinux_force_text_mode();

	write_serial(data);	/* write to serial port if needed */

	/* Write to screen? */
	if (DisplayCon & 0x01) {
		com32sys_t ireg, oreg;
		bool curxyok = false;
		uint16_t dx;

                memset(&ireg, 0, sizeof ireg);
		ireg.ebx.b[1] = *(uint8_t *)BIOS_page;
		ireg.eax.b[1] = 0x03; /* Read cursor position */
		__intcall(0x10, &ireg, &oreg);
		ireg.edx.l = oreg.edx.l;

		switch (data) {
		case 8:
			if (ireg.edx.b[0]--) {
				curxyok = true;
				break;
			}

			ireg.edx.b[0] = VidCols;
			if (ireg.edx.b[1]--) {
				curxyok = true;
				break;
			}

			ireg.edx.b[1] = 0;
			curxyok = true;
			break;
		case 13:
			ireg.edx.b[0] = 0;
			curxyok = true;
			break;
		case 10:
			break;
		default:
			dx = ireg.edx.w[0];

			ireg.ebx.b[1] = *(uint8_t *)BIOS_page;
			ireg.ebx.b[0] = 0x07; /* White on black */
			ireg.ecx.w[0] = 1;    /* One only */
			ireg.eax.b[0] = data;
			ireg.eax.b[1] = 0x09; /* Write char and attribute */
			__intcall(0x10, &ireg, NULL);

			ireg.edx.w[0] = dx;
			if (++ireg.edx.b[0] <= VidCols)
				curxyok = true;
			else
				ireg.edx.b[0] = 0;
		}

		if (!curxyok && ++ireg.edx.b[1] > VidRows) {
			/* Scroll */
			ireg.edx.b[1]--;
			ireg.ebx.b[1] = *(uint8_t *)BIOS_page;
			ireg.eax.b[1] = 0x02;
			__intcall(0x10, &ireg, NULL);

			ireg.eax.w[0] = 0x0601; /* Scroll up one line */
			ireg.ebx.b[1] = ScrollAttribute;
			ireg.ecx.w[0] = 0;
			ireg.edx.w[0] = ScreenSize; /* The whole screen */
			__intcall(0x10, &ireg, NULL);
		} else {
			ireg.ebx.b[1] = *(uint8_t *)BIOS_page;
			ireg.eax.b[1] = 0x02; /* Set cursor position */
			__intcall(0x10, &ireg, NULL);
		}
	}
}

void pm_writechr(com32sys_t *regs)
{
	writechr(regs->eax.b[0]);
}
