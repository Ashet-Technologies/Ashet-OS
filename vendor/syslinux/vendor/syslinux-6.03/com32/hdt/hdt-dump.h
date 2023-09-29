/* ----------------------------------------------------------------------- *
 *
 *   Copyright 20011 Erwan Velu - All Rights Reserved
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
#include <stdlib.h>
#include <ctype.h>
#include <bufprintf.h>
#include <zzjson/zzjson.h>
#include "hdt-common.h"

// Macros to manipulate Arrays
#define APPEND_ARRAY ZZJSON *temp_array; temp_array = zzjson_array_append(config, *item, zzjson_create_object(config,
#define APPEND_OBJECT_ARRAY(value) ZZJSON *temp_ar; temp_ar = zzjson_array_append(config, *item, value); *item=temp_ar; 
#define CREATE_ARRAY *item = zzjson_create_array(config, zzjson_create_object(config, 
#define add_ai(name,value) name,zzjson_create_number_i(config,value),
#define add_ahi(value) add_ai(#value,hardware->value)
#define add_as(name,value) name,zzjson_create_string(config,value),
#define add_ahs(value) add_as(#value,hardware->value)
#define END_OF_ARRAY NULL),NULL)
#define END_OF_APPEND NULL)); *item=temp_array;

// Macros to manipulate objects
#define CREATE_NEW_OBJECT   *item = zzjson_create_object(config, NULL);
#define FLUSH_OBJECT flush(config, item); 

// Macros to manipulate integers as objects
#define add_i(name,value) *item = zzjson_object_append(config, *item, name, zzjson_create_number_i(config, value))
#define add_hi(value) add_i(#value,hardware->value)

// Macros to manipulate strings as objects
#define add_s(name,value) *item = zzjson_object_append(config, *item, name, zzjson_create_string(config, value))
#define add_hs(value) add_s(#value,(char *)hardware->value)

// Macros to manipulate bool as objects
#define add_bool_true(name) *item = zzjson_object_append(config, *item, (char *)name, zzjson_create_true(config))
#define add_bool_false(name) *item = zzjson_object_append(config, *item, (char*)name, zzjson_create_false(config))
#define add_b(name,value) if (value==true) {add_bool_true(name);} else {add_bool_false(name);}
#define add_hb(value) add_b(#value,hardware->value)

extern struct print_buf p_buf;

void print_and_flush(ZZJSON_CONFIG *config, ZZJSON **item);
int dumpprintf(FILE *p, const char *format, ...);
void flush (ZZJSON_CONFIG *config, ZZJSON ** item);
void to_cpio(char *filename);

void dump_cpu(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item);
void dump_pxe(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item);
void dump_syslinux(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item);
void dump_vpd(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item);
void dump_vesa(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item);
void dump_disks(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item);
void dump_dmi(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item);
void dump_memory(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item);
void dump_pci(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item);
void dump_acpi(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item);
void dump_kernel(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item);
void dump_hdt(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item);
void dump(struct s_hardware *hardware);
