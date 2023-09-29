/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Erwan Velu - All Rights Reserved
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * -----------------------------------------------------------------------
 */

#ifndef DEFINE_HDT_ATA_H
#define DEFINE_HDT_ATA_H
#include <com32io.h>

#include <disk/geom.h>
#include "hdt.h"

struct ata_identify_device {
    unsigned short words000_009[10];
    unsigned char serial_no[20];
    unsigned short words020_022[3];
    unsigned char fw_rev[8];
    unsigned char model[40];
    unsigned short words047_079[33];
    unsigned short major_rev_num;
    unsigned short minor_rev_num;
    unsigned short command_set_1;
    unsigned short command_set_2;
    unsigned short command_set_extension;
    unsigned short cfs_enable_1;
    unsigned short word086;
    unsigned short csf_default;
    unsigned short words088_255[168];
} ATTR_PACKED;

struct ata_driveinfo {
    struct ata_identify_device aid;	/* IDENTIFY xxx DEVICE data */
    char host_bus_type[5];
    char interface_type[9];
    char interface_port;
} ATTR_PACKED;

/* Useless stuff until I manage how to send ata packets */
#ifdef ATA
enum {
    ATA_ID_FW_REV = 23,
    ATA_ID_PROD = 27,
    ATA_ID_FW_REV_LEN = 8,
    ATA_ID_PROD_LEN = 40,
};
void ata_id_c_string(const uint16_t * id, unsigned char *s, unsigned int ofs,
		     unsigned int len);
void ata_id_string(const uint16_t * id, unsigned char *s, unsigned int ofs,
		   unsigned int len);
void printregs(const com32sys_t * r);
#endif

#endif
