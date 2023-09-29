/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2011 Erwan Velu - All Rights Reserved
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

#include "hdt-common.h"
#include "hdt-dump.h"
#include <syslinux/config.h>

void dump_vesa(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {

	CREATE_NEW_OBJECT;
	add_hb(is_vesa_valid);
	if (hardware->is_vesa_valid) {
		char buffer[64]={0};
		snprintf(buffer,sizeof(buffer),"%d.%d", hardware->vesa.major_version, hardware->vesa.minor_version);
		add_s("vesa.version",buffer);
		add_hs(vesa.vendor);
		add_hs(vesa.product);
		add_hs(vesa.product_revision);
		add_hi(vesa.software_rev);
		memset(buffer,0,sizeof(buffer));
		snprintf(buffer,sizeof(buffer),"%d KB",hardware->vesa.total_memory*64);
		add_s("vesa.memory",buffer);
		add_i("vesa.modes",hardware->vesa.vmi_count);
		FLUSH_OBJECT;
		for (int i = 0; i < hardware->vesa.vmi_count; i++) {
		        struct vesa_mode_info *mi = &hardware->vesa.vmi[i].mi;
		        if ((mi->h_res == 0) || (mi->v_res == 0))
				continue;
			CREATE_NEW_OBJECT;
			memset(buffer,0,sizeof(buffer));
			snprintf(buffer,sizeof(buffer),"0x%04x",hardware->vesa.vmi[i].mode + 0x200);
			add_s("vesa.kernel_mode",buffer);
			add_i("vesa.hres",mi->h_res);
			add_i("vesa.vres",mi->v_res);
			add_i("vesa.bpp",mi->bpp);
			FLUSH_OBJECT;
		}
	} else {
		FLUSH_OBJECT;
	}
	to_cpio("vesa");
}
