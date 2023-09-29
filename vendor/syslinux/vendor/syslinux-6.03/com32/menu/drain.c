#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/cpu.h>

void drain_keyboard(void)
{
    /* Prevent "ghost typing" and keyboard buffer snooping */
    volatile char junk;
    int rv;

    do {
	rv = read(0, (char *)&junk, 1);
    } while (rv > 0);

    junk = 0;

    cli();
    *(volatile uint8_t *)0x419 = 0;	/* Alt-XXX keyboard area */
    *(volatile uint16_t *)0x41a = 0x1e;	/* Keyboard buffer empty */
    *(volatile uint16_t *)0x41c = 0x1e;
    memset((void *)0x41e, 0, 32);	/* Clear the actual keyboard buffer */
    sti();
}
