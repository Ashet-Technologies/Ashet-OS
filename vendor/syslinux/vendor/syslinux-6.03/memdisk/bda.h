/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2001-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <stdint.h>

/* Addresses in the zero page */
#define BIOS_INT13	(0x13*4)	/* INT 13h vector */
#define BIOS_INT15	(0x15*4)	/* INT 15h vector */
#define BIOS_INT1E	(0x1E*4)	/* INT 1Eh vector */
#define BIOS_INT40	(0x40*4)	/* INT 13h vector */
#define BIOS_INT41	(0x41*4)	/* INT 41h vector */
#define BIOS_INT46	(0x46*4)	/* INT 46h vector */
#define BIOS_BASEMEM	0x413		/* Amount of DOS memory */
#define BIOS_EQUIP	0x410		/* BIOS equipment list */
#define BIOS_HD_COUNT	0x475		/* Number of hard drives present */

/* Access to objects in the zero page */
static inline void wrz_8(uint32_t addr, uint8_t data)
{
    *((uint8_t *) addr) = data;
}

static inline void wrz_16(uint32_t addr, uint16_t data)
{
    *((uint16_t *) addr) = data;
}

static inline void wrz_32(uint32_t addr, uint32_t data)
{
    *((uint32_t *) addr) = data;
}

static inline uint8_t rdz_8(uint32_t addr)
{
    return *((uint8_t *) addr);
}

static inline uint16_t rdz_16(uint32_t addr)
{
    return *((uint16_t *) addr);
}

static inline uint32_t rdz_32(uint32_t addr)
{
    return *((uint32_t *) addr);
}
