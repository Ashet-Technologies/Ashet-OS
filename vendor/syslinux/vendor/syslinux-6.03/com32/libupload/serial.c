#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <console.h>
#include <sys/io.h>
#include <sys/cpu.h>
#include <syslinux/config.h>

#include "serial.h"

enum {
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


int serial_init(struct serial_if *sif, const char *argv[])
{
    const struct syslinux_serial_console_info *sci
	= syslinux_serial_console_info();
    uint16_t port;
    unsigned int divisor;
    uint8_t dll, dlm, lcr;

    if (!argv[0]) {
	if (sci->iobase) {
	    port = sci->iobase;
	} else {
	    printf("No port number specified and not using serial console!\n");
	    return -1;
	}
    } else {
	port = strtoul(argv[0], NULL, 0);
	if (port <= 3) {
	    uint16_t addr = ((uint16_t *)0x400)[port];
	    if (!addr) {
		printf("No serial port address found!\n");
	    return -1;
	    }
	    printf("Serial port %u is at 0x%04x\n", port, addr);
	    port = addr;
	}
    }

    sif->port = port;
    sif->console = false;

    divisor = 1;		/* Default speed = 115200 bps */

    /* Check to see if this is the same as the serial console */
    if (port == sci->iobase) {
	/* Overlaying the console... */
	sif->console = true;

	/* Default to already configured speed */
	divisor = sci->divisor;

	/* Shut down I/O to the console for the time being */
	openconsole(&dev_null_r, &dev_null_w);
    }

    if (argv[0] && argv[1])
	divisor = 115200/strtoul(argv[1], NULL, 0);

    cli();			/* Just in case... */

    /* Save old register settings */
    sif->old.lcr = inb(port + LCR);
    sif->old.mcr = inb(port + MCR);
    sif->old.iir = inb(port + IIR);

    /* Set speed */
    outb(0x83, port + LCR);	/* Enable divisor access */
    sif->old.dll = inb(port + DLL);
    sif->old.dlm = inb(port + DLM);
    outb(divisor, port + DLL);
    outb(divisor >> 8, port + DLM);
    (void)inb(port + IER);	/* Synchronize */

    dll = inb(port + DLL);
    dlm = inb(port + DLM);
    lcr = inb(port + LCR);
    outb(0x03, port + LCR);	/* Enable data access, n81 */
    (void)inb(port + IER);	/* Synchronize */
    sif->old.ier = inb(port + IER);

    /* Disable interrupts */
    outb(0, port + IER);

    sti();

    if (dll != (uint8_t)divisor ||
	dlm != (uint8_t)(divisor >> 8) ||
	lcr != 0x83) {
	serial_cleanup(sif);
	printf("No serial port detected!\n");
	return -1;		/* This doesn't look like a serial port */
    }

    /* Enable 16550A FIFOs if available */
    outb(0x01, port + FCR);	/* Enable FIFO */
    (void)inb(port + IER);	/* Synchronize */
    if (inb(port + IIR) < 0xc0)
	outb(0x00, port + FCR);	/* Disable FIFOs if non-functional */
    (void)inb(port + IER);	/* Synchronize */

    return 0;
}

void serial_write(struct serial_if *sif, const void *data, size_t n)
{
    uint16_t port = sif->port;
    const char *p = data;
    uint8_t lsr;

    while (n--) {
	do {
	    lsr = inb(port + LSR);
	} while (!(lsr & 0x20));

	outb(*p++, port + THR);
    }
}

void serial_read(struct serial_if *sif, void *data, size_t n)
{
    uint16_t port = sif->port;
    char *p = data;
    uint8_t lsr;

    while (n--) {
	do {
	    lsr = inb(port + LSR);
	} while (!(lsr & 0x01));

	*p++ = inb(port + RBR);
    }
}

void serial_cleanup(struct serial_if *sif)
{
    uint16_t port = sif->port;

    outb(0x83, port + LCR);
    (void)inb(port + IER);
    outb(sif->old.dll, port + DLL);
    outb(sif->old.dlm, port + DLM);
    (void)inb(port + IER);
    outb(sif->old.lcr & 0x7f, port + LCR);
    (void)inb(port + IER);
    outb(sif->old.mcr, port + MCR);
    outb(sif->old.ier, port + IER);
    if (sif->old.iir < 0xc0)
	outb(0x00, port + FCR);	/* Disable FIFOs */

    /* Re-enable console messages, if we shut them down */
    if (sif->console)
	openconsole(&dev_null_r, &dev_stdcon_w);
}
