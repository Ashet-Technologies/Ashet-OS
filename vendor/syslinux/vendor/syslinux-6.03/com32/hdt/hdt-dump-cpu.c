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

void dump_cpu(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {

        CREATE_NEW_OBJECT;
	add_hs(cpu.vendor);
	add_hs(cpu.model);
	add_hi(cpu.vendor_id);
	add_hi(cpu.family);
	add_hi(cpu.model_id);
	add_hi(cpu.stepping);
	add_hi(cpu.num_cores);
	add_hi(cpu.l1_data_cache_size);
	add_hi(cpu.l1_instruction_cache_size);
	add_hi(cpu.l2_cache_size);
	size_t i;
	for (i = 0; i < cpu_flags_count; i++) {
		char temp[128]={0};
		snprintf(temp,sizeof(temp),"cpu.flags.%s",cpu_flags_names[i]);
		add_b(temp,get_cpu_flag_value_from_name(&hardware->cpu,cpu_flags_names[i]));
	}
	FLUSH_OBJECT;
	to_cpio("cpu");
}
