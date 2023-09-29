/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2010 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <stdint.h>
#include <stdbool.h>
#include <netinet/in.h>
#include "pxe.h"

/* Port number bitmap - port numbers 49152 (0xc000) to 57343 (0xefff) */
#define PORT_NUMBER_BASE	49152
#define PORT_NUMBER_COUNT	8192 /* Power of 2, please */
static uint32_t port_number_bitmap[PORT_NUMBER_COUNT/32];
static uint16_t first_port_number /* = 0 */;

/*
 * Bitmap functions
 */
static bool test_bit(const uint32_t *bitmap, int32_t index)
{
    uint8_t st;
    asm("btl %2,%1 ; setc %0" : "=qm" (st) : "m" (*bitmap), "r" (index));
    return st;
}

static void set_bit(uint32_t *bitmap, int32_t index)
{
    asm volatile("btsl %1,%0" : "+m" (*bitmap) : "r" (index) : "memory");
}

static void clr_bit(uint32_t *bitmap, int32_t index)
{
    asm volatile("btcl %1,%0" : "+m" (*bitmap) : "r" (index) : "memory");
}

/*
 * Get and free a port number (host byte order)
 */
uint16_t get_port(void)
{
    uint16_t port;

    do {
	port = first_port_number++;
	first_port_number &= PORT_NUMBER_COUNT - 1;
    } while (test_bit(port_number_bitmap, port));

    set_bit(port_number_bitmap, port);
    return htons(port + PORT_NUMBER_BASE);
}

void free_port(uint16_t port)
{
    port = ntohs(port) - PORT_NUMBER_BASE;

    if (port >= PORT_NUMBER_COUNT)
	return;

    clr_bit(port_number_bitmap, port);
}
