/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009-2011 Erwan Velu - All Rights Reserved
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

#include <stdio.h>
#include <string.h>
#include <memory.h>
#include <dprintf.h>
#include "acpi/acpi.h"

void parse_fadt(s_fadt * f)
{
    /* Let's seach for FADT table */
    uint8_t *q;

    /* Fixing table name */
    memcpy(f->header.signature,FADT,sizeof(FADT));
    
    /* Copying remaining structs */
    q = (uint8_t *)f->address;
    q += ACPI_HEADER_SIZE;
    DEBUG_PRINT(("- Parsing FADT at %p\n",q));

    cp_struct(&f->firmware_ctrl);
    cp_struct(&f->dsdt_address);
    cp_struct(&f->reserved);
    cp_struct(&f->prefered_pm_profile);
    cp_struct(&f->sci_int);
    cp_struct(&f->smi_cmd);
    cp_struct(&f->acpi_enable);
    cp_struct(&f->acpi_disable);
    cp_struct(&f->s4bios_req);
    cp_struct(&f->pstate_cnt);
    cp_struct(&f->pm1a_evt_blk);
    cp_struct(&f->pm1b_evt_blk);
    cp_struct(&f->pm1a_cnt_blk);
    cp_struct(&f->pm1b_cnt_blk);
    cp_struct(&f->pm2_cnt_blk);
    cp_struct(&f->pm_tmr_blk);
    cp_struct(&f->gpe0_blk);
    cp_struct(&f->gpe1_blk);
    cp_struct(&f->pm1_evt_len);
    cp_struct(&f->pm1_cnt_len);
    cp_struct(&f->pm2_cnt_len);
    cp_struct(&f->pm_tmr_len);
    cp_struct(&f->gpe0_blk_len);
    cp_struct(&f->gpe1_blk_len);
    cp_struct(&f->gpe1_base);
    cp_struct(&f->cst_cnt);
    cp_struct(&f->p_lvl2_lat);
    cp_struct(&f->p_lvl3_lat);
    cp_struct(&f->flush_size);
    cp_struct(&f->flush_stride);
    cp_struct(&f->duty_offset);
    cp_struct(&f->duty_width);
    cp_struct(&f->day_alarm);
    cp_struct(&f->mon_alarm);
    cp_struct(&f->century);
    cp_struct(&f->iapc_boot_arch);
    cp_struct(&f->reserved_2);
    cp_struct(&f->flags);
    cp_struct(&f->reset_reg);
    cp_struct(&f->reset_value);
    cp_struct(f->reserved_3);
    cp_struct(&f->x_firmware_ctrl);
    cp_struct(&f->x_dsdt);
    cp_struct(&f->x_pm1a_evt_blk);
    cp_struct(&f->x_pm1b_evt_blk);
    cp_struct(&f->x_pm1a_cnt_blk);
    cp_struct(&f->x_pm1b_cnt_blk);
    cp_struct(&f->x_pm2_cnt_blk);
    cp_struct(&f->x_pm_tmr_blk);
    cp_struct(&f->x_gpe0_blk);
    cp_struct(&f->x_gpe1_blk);
}
