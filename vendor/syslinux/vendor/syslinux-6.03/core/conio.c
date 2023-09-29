/*
 * -----------------------------------------------------------------------
 *
 *   Copyright 1994-2008 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2014 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * -----------------------------------------------------------------------
 *
 *
 * conio.c
 *
 * Console I/O code, except:
 *   writechr, writestr_early	- module-dependent
 *   writestr, crlf		- writestr.inc
 *   writehex*			- writehex.inc
 */
#include <sys/io.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <fs.h>
#include <com32.h>
#include <sys/cpu.h>
#include <syslinux/firmware.h>

#include "bios.h"
#include "graphics.h"

union screen _cursor;
union screen _screensize;

/*
 * Serial console stuff.
 */
__export uint16_t SerialPort = 0;   /* Serial port base (or 0 for no serial port) */
__export uint8_t FlowInput = 0;	    /* Input bits for serial flow */
__export uint16_t BaudDivisor = 115200/9600; /* Baud rate divisor */
__export uint8_t FlowIgnore = 0;    /* Ignore input unless these bits set */
__export uint16_t DisplayCon = 0x01;	/* Display console enabled */
__export uint8_t FlowOutput = 0;	/* Output to assert for serial flow */

__export uint8_t DisplayMask = 0x07;	/* Display modes mask */

uint8_t ScrollAttribute = 0x07; /* Grey on white (normal text color) */

/*
 * loadkeys:	Load a LILO-style keymap
 *
 * Returns 0 on success, or -1 on error.
 */
__export int loadkeys(const char *filename)
{
	FILE *f;

	f = fopen(filename, "r");
	if (!f)
		return -1;

	fread(KbdMap, 1, sizeof(KbdMap), f);

	fclose(f);
	return 0;
}

/*
 * write_serial: If serial output is enabled, write character on
 * serial port.
 */
__export void write_serial(char data)
{
	if (!SerialPort)
		return;

	if (!(DisplayMask & 0x04))
		return;

	while (1) {
		char ch;

		ch = inb(SerialPort + 5); /* LSR */

		/* Wait for space in transmit register */
		if (!(ch & 0x20))
			continue;

		/* Wait for input flow control */
		ch = inb(SerialPort + 6);
		ch &= FlowInput;
		if (ch != FlowInput)
			continue;

		break;
	}

	outb(data, SerialPort);	/* Send data */
	io_delay();
}

void pm_write_serial(com32sys_t *regs)
{
	write_serial(regs->eax.b[0]);
}

void serialcfg(uint16_t *iobase, uint16_t *divisor, uint16_t *flowctl)
{
	uint8_t al, ah;

	*iobase = SerialPort;
	*divisor = BaudDivisor;

	al = FlowOutput;
	ah = FlowInput;

	al |= ah;
	ah = FlowIgnore;
	ah >>= 4;

	if (!DisplayCon)
		ah |= 0x80;

	*flowctl = al | (ah << 8);
}

void pm_serialcfg(com32sys_t *regs)
{
	serialcfg(&regs->eax.w[0], &regs->ecx.w[0], &regs->ebx.w[0]);
}

/*
 * write_serial_str: write_serial for strings
 */
__export void write_serial_str(char *data)
{
	char ch;

	while ((ch = *data++))
		write_serial(ch);
}

/*
 * pollchar: check if we have an input character pending
 *
 * Returns 1 if character pending.
 */
int bios_pollchar(void)
{
	com32sys_t ireg, oreg;
	uint8_t data = 0;

	memset(&ireg, 0, sizeof(ireg));

	ireg.eax.b[1] = 0x11;	/* Poll keyboard */
	__intcall(0x16, &ireg, &oreg);

	if (!(oreg.eflags.l & EFLAGS_ZF))
		return 1;

	if (SerialPort) {
		cli();

		/* Already-queued input? */
		if (SerialTail == SerialHead) {
			/* LSR */
			data = inb(SerialPort + 5) & 1;
			if (data) {
				/* MSR */
				data = inb(SerialPort + 6);

				/* Required status bits */
				data &= FlowIgnore;

				if (data == FlowIgnore)
					data = 1;
				else
					data = 0;
			}
		} else
			data = 1;
		sti();
	}

	return data;
}

__export int pollchar(void)
{
	return firmware->i_ops->pollchar();
}

void pm_pollchar(com32sys_t *regs)
{
	if (pollchar())
		regs->eflags.l &= ~EFLAGS_ZF;
	else
		regs->eflags.l |= EFLAGS_ZF;
}

char bios_getchar(char *hi)
{
	com32sys_t ireg, oreg;
	unsigned char data;

	memset(&ireg, 0, sizeof(ireg));
	memset(&oreg, 0, sizeof(oreg));
	while (1) {
		__idle();

		ireg.eax.b[1] = 0x11;	/* Poll keyboard */
		__intcall(0x16, &ireg, &oreg);

		if (oreg.eflags.l & EFLAGS_ZF) {
			if (!SerialPort)
				continue;

			cli();
			if (SerialTail != SerialHead) {
				/* serial queued */
				sti(); /* We already know we'll consume data */
				data = *SerialTail++;

				if (SerialTail > SerialHead + serial_buf_size)
					SerialTail = SerialHead;
			} else {
				/* LSR */
				data = inb(SerialPort + 5) & 1;
				if (!data) {
					sti();
					continue;
				}
				data = inb(SerialPort + 6);
				data &= FlowIgnore;
				if (data != FlowIgnore) {
					sti();
					continue;
				}

				data = inb(SerialPort);
				sti();
				break;
			}
		} else {
			/* Keyboard input? */
			ireg.eax.b[1] = 0x10; /* Get keyboard input */
			__intcall(0x16, &ireg, &oreg);

			data = oreg.eax.b[0];
			*hi = oreg.eax.b[1];

			if (data == 0xE0)
				data = 0;

			if (data) {
				/* Convert character sets */
				data = KbdMap[data];
			}
		}

		break;
	}

	reset_idle();		/* Character received */
	return data;
}

uint8_t bios_shiftflags(void)
{
	com32sys_t reg;
	uint8_t ah, al;

	memset(&reg, 0, sizeof reg);
	reg.eax.b[1] = 0x12;
	__intcall(0x16, &reg, &reg);
	ah = reg.eax.b[1];
	al = reg.eax.b[0];

	/*
	 * According to the Interrupt List, "many machines" don't correctly
	 * fold the Alt state, presumably because it might be AltGr.
	 * Explicitly fold the Alt and Ctrl states; it fits our needs
	 * better.
	 */

	if (ah & 0x0a)
		al |= 0x08;
	if (ah & 0x05)
		al |= 0x04;

	return al;
}

__export uint8_t kbd_shiftflags(void)
{
	if (firmware->i_ops->shiftflags)
		return firmware->i_ops->shiftflags();
	else
		return 0;	/* Unavailable on this firmware */
}

/*
 * getchar: Read a character from keyboard or serial port
 */
__export char getchar(char *hi)
{
	return firmware->i_ops->getchar(hi);
}

void pm_getchar(com32sys_t *regs)
{
	regs->eax.b[0] = getchar((char *)&regs->eax.b[1]);
}
