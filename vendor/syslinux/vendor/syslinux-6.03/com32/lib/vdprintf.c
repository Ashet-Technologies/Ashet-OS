/*
 * vdprintf.c
 */

#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <inttypes.h>
#include <sys/io.h>
#include <sys/cpu.h>

#ifdef DEBUG_PORT

#define BUFFER_SIZE	4096

enum serial_port_regs {
    THR = 0,
    RBR = 0,
    DLL = 0,
    DLM = 1,
    IER = 1,
    IIR = 2,
    FCR = 2,
    LCR = 3,
    MCR = 4,
    LSR = 5,
    MSR = 6,
    SCR = 7,
};

static const uint16_t debug_base = DEBUG_PORT;

static void debug_putc(char c)
{
    if (c == '\n')
	debug_putc('\r');

    while ((inb(debug_base + LSR) & 0x20) == 0)
	cpu_relax();
    outb(c, debug_base + THR);
}

void vdprintf(const char *format, va_list ap)
{
    int rv;
    char buffer[BUFFER_SIZE];
    char *p;
    static bool debug_init = false;
    static bool debug_ok   = false;

    rv = vsnprintf(buffer, BUFFER_SIZE, format, ap);
    if (rv < 0)
	return;

    if (rv > BUFFER_SIZE - 1)
	rv = BUFFER_SIZE - 1;

    /*
     * This unconditionally outputs to a serial port at 0x3f8 regardless of
     * if one is enabled or not (this means we don't have to enable the real
     * serial console and therefore get conflicting output.)
     */
    if (__unlikely(!debug_init)) {
	uint8_t dll, dlm, lcr;

	debug_init = true;

	cli();

	/* Initialize the serial port to 115200 n81 with FIFOs enabled */
	outb(0x83, debug_base + LCR);
	outb(0x01, debug_base + DLL);
	outb(0x00, debug_base + DLM);
	(void)inb(debug_base + IER);	/* Synchronize */
	dll = inb(debug_base + DLL);
	dlm = inb(debug_base + DLM);
	lcr = inb(debug_base + LCR);
	
	outb(0x03, debug_base + LCR);
	(void)inb(debug_base + IER);	/* Synchronize */

	outb(0x00, debug_base + IER);
	(void)inb(debug_base + IER);	/* Synchronize */

	sti();

	if (dll != 0x01 || dlm != 0x00 || lcr != 0x83) {
	    /* No serial port present */
	    return;
	}

	outb(0x01, debug_base + FCR);
	(void)inb(debug_base + IER);	/* Synchronize */
	if (inb(debug_base + IIR) < 0xc0) {
	    outb(0x00, debug_base + FCR); /* Disable non-functional FIFOs */
	    (void)inb(debug_base + IER);	/* Synchronize */
	}

	debug_ok = true;
    }

    if (!debug_ok)
	return;

    p = buffer;
    while (rv--)
	debug_putc(*p++);
}

#endif /* DEBUG_PORT */
