/*
 * -----------------------------------------------------------------------
 *
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * -----------------------------------------------------------------------
 *
 * serirq.c
 *
 * Serial port IRQ code
 *
 * We don't know what IRQ, if any, we have, so map all of them...
 */
#include <sys/io.h>
#include <string.h>

#include <fs.h>
#include "bios.h"

static char serial_buf[serial_buf_size];

static unsigned short SerialIRQPort; /* Serial port w IRQ service */
char *SerialHead = serial_buf;    /* Head of serial port rx buffer */
char *SerialTail = serial_buf;    /* Tail of serial port rx buffer */

static unsigned char IRQMask[2];	     /* PIC IRQ mask status */

static unsigned int oldirq[16];

typedef void (*irqhandler_t)(void);

void sirq_cleanup(void);

static void irq_common(unsigned short old_irq)
{
	char *dst;
	irqhandler_t next;
	char val;

	dst = SerialHead;
	next = (irqhandler_t)oldirq[old_irq];

	/* LSR */
	val = inb(SerialPort + 5);

	/* Received data */
	while (val & 1) {
		/* RDR */
		*dst++ = inb(SerialPort);
		/* LSR */
		val = inb(SerialPort + 5);
		if ((val & FlowIgnore) == FlowIgnore) {
			/* Wrap around if necessary */
			dst = (char *)((unsigned long)dst & (serial_buf_size - 1));

			/* Would this cause overflow? */
			if (dst != SerialTail)
				SerialHead = dst;
		}
	}

	/* Chain to next handler */
	next();
}

#define SERIAL_IRQ_HANDLER(n) \
	static void serstub_irq##n(void)	\
	{					\
		irq_common(n);			\
	}

SERIAL_IRQ_HANDLER(0);
SERIAL_IRQ_HANDLER(1);
SERIAL_IRQ_HANDLER(2);
SERIAL_IRQ_HANDLER(3);
SERIAL_IRQ_HANDLER(4);
SERIAL_IRQ_HANDLER(5);
SERIAL_IRQ_HANDLER(6);
SERIAL_IRQ_HANDLER(7);
SERIAL_IRQ_HANDLER(8);
SERIAL_IRQ_HANDLER(9);
SERIAL_IRQ_HANDLER(10);
SERIAL_IRQ_HANDLER(11);
SERIAL_IRQ_HANDLER(12);
SERIAL_IRQ_HANDLER(13);
SERIAL_IRQ_HANDLER(14);
SERIAL_IRQ_HANDLER(15);

static inline void save_irq_vectors(uint32_t *src, uint32_t *dst)
{
	int i;

	for (i = 0; i < 8; i++)
		*dst++ = *src++;
}

static inline void install_irq_vectors(uint32_t *dst, int first)
{
	if (first) {
		*dst++ = (uint32_t)serstub_irq0;
		*dst++ = (uint32_t)serstub_irq1;
		*dst++ = (uint32_t)serstub_irq2;
		*dst++ = (uint32_t)serstub_irq3;
		*dst++ = (uint32_t)serstub_irq4;
		*dst++ = (uint32_t)serstub_irq5;
		*dst++ = (uint32_t)serstub_irq6;
		*dst++ = (uint32_t)serstub_irq7;
	} else {
		*dst++ = (uint32_t)serstub_irq8;
		*dst++ = (uint32_t)serstub_irq9;
		*dst++ = (uint32_t)serstub_irq10;
		*dst++ = (uint32_t)serstub_irq11;
		*dst++ = (uint32_t)serstub_irq12;
		*dst++ = (uint32_t)serstub_irq13;
		*dst++ = (uint32_t)serstub_irq14;
		*dst++ = (uint32_t)serstub_irq15;
	}
}

__export void sirq_install(void)
{
	char val, val2;

	sirq_cleanup();

	save_irq_vectors((uint32_t *)(4 * 0x8), oldirq);
	save_irq_vectors((uint32_t *)(4 * 0x70), &oldirq[8]);

	install_irq_vectors((uint32_t *)(4 * 0x8), 1);
	install_irq_vectors((uint32_t *)(4 * 0x70), 0);

	SerialIRQPort = SerialPort;

	/* Clear DLAB (should already be...) */
	outb(0x3, SerialIRQPort + 5);
	io_delay();

	/* Enable receive interrupt */
	outb(0x1, SerialIRQPort + 1);
	io_delay();

	/*
	 * Enable all the interrupt lines at the PIC. Some BIOSes only
	 * enable the timer interrupts and other interrupts actively
	 * in use by the BIOS.
	 */

	/* Secondary PIC mask register */
	val = inb(0xA1);
	val2 = inb(0x21);
	IRQMask[0] = val;
	IRQMask[1] = val2;

	io_delay();

	/* Remove all interrupt masks */
	outb(0x21, 0);
	outb(0xA1, 0);
}

__export void sirq_cleanup_nowipe(void)
{
	uint32_t *dst;
	int i;

	if (!SerialIRQPort)
		return;

	/* Clear DLAB */
	outb(0x3, SerialIRQPort + 5);
	io_delay();

	/* Clear IER */
	outb(0x0, SerialIRQPort + 1);
	io_delay();

	/* Restore PIC masks */
	outb(IRQMask[0], 0x21);
	outb(IRQMask[1], 0xA1);

	/* Restore the original interrupt vectors */
	dst = (uint32_t *)(4 * 0x8);
	for (i = 0; i < 8; i++)
		*dst++ = oldirq[i];

	dst = (uint32_t *)(4 * 0x70);
	for (i = 8; i < 16; i++)
		*dst++ = oldirq[i];

	/* No active interrupt system */
	SerialIRQPort = 0;
}

void sirq_cleanup(void)
{
	sirq_cleanup_nowipe();
	memcpy(SerialHead, 0x0, serial_buf_size);
}
