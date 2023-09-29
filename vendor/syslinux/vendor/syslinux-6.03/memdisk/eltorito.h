/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009-2010 Shao Miller - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * eltorito.h
 *
 * EDD-4 El Torito structures and debugging routines
 */

#include <stdint.h>
#include "compiler.h"

/* EDD-4 Bootable Optical Disc Drive Boot Volume Descriptor */
MEMDISK_PACKED_PREFIX
struct edd4_bvd {
    uint8_t boot_rec_ind;	/* Boot Record Indicator */
    uint8_t iso9660_id[5];	/* ISO9660 ID            */
    uint8_t ver;		/* Descriptor Version    */
    uint8_t eltorito[32];	/* "EL TORITO" etc.      */
    uint8_t res1[32];		/* Reserved              */
    uint32_t boot_cat;		/* Boot catalog sector   */
    uint8_t res2[1973];		/* Reserved              */
} MEMDISK_PACKED_POSTFIX;

MEMDISK_PACKED_PREFIX
struct validation_entry {
    uint8_t header_id;		/* Header ID                      */
    uint8_t platform_id;	/* Platform ID                    */
    uint16_t res1;		/* Reserved                       */
    uint8_t id_string[24];	/* Manufacturer                   */
    uint16_t checksum;		/* Sums with whole record to zero */
    uint8_t key55;		/* Key byte 0x55                  */
    uint8_t keyAA;		/* Key byte 0xAA                  */
} MEMDISK_PACKED_POSTFIX;

MEMDISK_PACKED_PREFIX
struct initial_entry {
    uint8_t header_id;		/* Header ID                */
    uint8_t media_type;		/* Media type               */
    uint16_t load_seg;		/* Load segment             */
    uint8_t system_type;	/* (Filesystem ID)          */
    uint8_t res1;		/* Reserved                 */
    uint16_t sect_count;	/* Emulated sectors to load */
    uint32_t load_block;	/* Starting sector of image */
    uint8_t res2[4];		/* Reserved                 */
} MEMDISK_PACKED_POSTFIX;

/* EDD-4 Bootable Optical Disc Drive Boot Catalog (fixed-size portions) */
MEMDISK_PACKED_PREFIX
struct edd4_bootcat {
    struct validation_entry validation_entry;
    struct initial_entry initial_entry;
} MEMDISK_PACKED_POSTFIX;

/* EDD-4 CD Specification Packet */
MEMDISK_PACKED_PREFIX
struct edd4_cd_pkt {
    uint8_t size;		/* Packet size                     */
    uint8_t type;		/* Boot media type (flags)         */
    uint8_t driveno;		/* INT 13h drive number            */
    uint8_t controller;		/* Controller index                */
    uint32_t start;		/* Starting LBA of image           */
    uint16_t devno;		/* Device number                   */
    uint16_t userbuf;		/* User buffer segment             */
    uint16_t load_seg;		/* Load segment                    */
    uint16_t sect_count;	/* Emulated sectors to load        */
    uint8_t geom1;		/* Cylinders bits 0 thru 7         */
    uint8_t geom2;		/* Sects/track 0 thru 5, cyls 8, 9 */
    uint8_t geom3;		/* Heads                           */
} MEMDISK_PACKED_POSTFIX;

