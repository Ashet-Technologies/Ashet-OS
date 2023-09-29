/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2003-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
 *   Copyright 2010 Shao Miller
 *   Copyright 2010-2012 Michal Soltys
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
 * ----------------------------------------------------------------------- */

#ifndef COM32_CHAIN_MANGLE_H
#define COM32_CHAIN_MANGLE_H

#include "chain.h"
#include "partiter.h"

/* file's manglers */
int manglef_isolinux(struct data_area *data);
int manglef_grub(const struct part_iter *iter, struct data_area *data);
int manglef_bpb(const struct part_iter *iter, struct data_area *data);
/* int manglef_drmk(struct data_area *data);*/

/* sector's manglers */
int mangles_bpb(const struct part_iter *iter, struct data_area *data);
int mangles_save(const struct part_iter *iter, const struct data_area *data, void *org);
int mangles_cmldr(struct data_area *data);

/* sector + file's manglers */
int manglesf_bss(struct data_area *sec, struct data_area *fil);

/* registers' manglers */
int mangler_init(const struct part_iter *iter);
int mangler_handover(const struct part_iter *iter, const struct data_area *data);
int mangler_grldr(const struct part_iter *iter);

/* partition layout's manglers */
int manglepe_fixchs(struct part_iter *miter);
int manglepe_hide(struct part_iter *miter);

#endif

/* vim: set ts=8 sts=4 sw=4 noet: */
