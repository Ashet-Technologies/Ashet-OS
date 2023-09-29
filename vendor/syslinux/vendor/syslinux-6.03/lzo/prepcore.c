/* ----------------------------------------------------------------------- *
 *   
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/* 
   This file is based in part on:

   precomp2.c -- example program: how to generate pre-compressed data

   This file is part of the LZO real-time data compression library.

   Copyright (C) 2008 Markus Franz Xaver Johannes Oberhumer
   Copyright (C) 2007 Markus Franz Xaver Johannes Oberhumer
   Copyright (C) 2006 Markus Franz Xaver Johannes Oberhumer
   Copyright (C) 2005 Markus Franz Xaver Johannes Oberhumer
   Copyright (C) 2004 Markus Franz Xaver Johannes Oberhumer
   Copyright (C) 2003 Markus Franz Xaver Johannes Oberhumer
   Copyright (C) 2002 Markus Franz Xaver Johannes Oberhumer
   Copyright (C) 2001 Markus Franz Xaver Johannes Oberhumer
   Copyright (C) 2000 Markus Franz Xaver Johannes Oberhumer
   Copyright (C) 1999 Markus Franz Xaver Johannes Oberhumer
   Copyright (C) 1998 Markus Franz Xaver Johannes Oberhumer
   Copyright (C) 1997 Markus Franz Xaver Johannes Oberhumer
   Copyright (C) 1996 Markus Franz Xaver Johannes Oberhumer
   All Rights Reserved.

   The LZO library is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License as
   published by the Free Software Foundation; either version 2 of
   the License, or (at your option) any later version.

   The LZO library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with the LZO library; see the file COPYING.
   If not, write to the Free Software Foundation, Inc.,
   51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

   Markus F.X.J. Oberhumer
   <markus@oberhumer.com>
   http://www.oberhumer.com/opensource/lzo/
 */

#include "lzo/lzoconf.h"
#include "lzo/lzo1x.h"

LZO_EXTERN(int)
lzo1x_999_compress_internal(const lzo_bytep in, lzo_uint in_len,
			    lzo_bytep out, lzo_uintp out_len,
			    lzo_voidp wrkmem,
			    const lzo_bytep dict, lzo_uint dict_len,
			    lzo_callback_p cb,
			    int try_lazy,
			    lzo_uint good_length,
			    lzo_uint max_lazy,
			    lzo_uint nice_length,
			    lzo_uint max_chain, lzo_uint32 flags);

LZO_EXTERN(int)
lzo1y_999_compress_internal(const lzo_bytep in, lzo_uint in_len,
			    lzo_bytep out, lzo_uintp out_len,
			    lzo_voidp wrkmem,
			    const lzo_bytep dict, lzo_uint dict_len,
			    lzo_callback_p cb,
			    int try_lazy,
			    lzo_uint good_length,
			    lzo_uint max_lazy,
			    lzo_uint nice_length,
			    lzo_uint max_chain, lzo_uint32 flags);

#define PARANOID 1

#include <assert.h>
#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#ifdef __GNUC__
# define noreturn void __attribute__((noreturn))
#else
# define noreturn void
#endif

struct prefix {
    uint32_t pfx_start;
    uint32_t pfx_compressed;
    uint32_t pfx_cdatalen;
    uint32_t pfx_checksum;
    uint32_t pfx_maxlma;
};

static inline uint32_t get_32(const uint32_t * p)
{
#if defined(__i386__) || defined(__x86_64__)
    /* Littleendian and unaligned-capable */
    return *p;
#else
    const uint8_t *pp = (const uint8_t *)p;
    return (uint32_t) pp[0] + ((uint32_t) pp[1] << 8) +
	((uint32_t) pp[2] << 16) + ((uint32_t) pp[3] << 24);
#endif
}

static inline void set_32(uint32_t * p, uint32_t v)
{
#if defined(__i386__) || defined(__x86_64__)
    /* Littleendian and unaligned-capable */
    *p = v;
#else
    uint8_t *pp = (uint8_t *) p;
    pp[0] = (v & 0xff);
    pp[1] = ((v >> 8) & 0xff);
    pp[2] = ((v >> 16) & 0xff);
    pp[3] = ((v >> 24) & 0xff);
#endif
}

const char *progname = NULL;
const char *in_name  = NULL;
const char *out_name = NULL;

static noreturn error(const char *fmt, ...)
{
    va_list ap;

    va_start(ap, fmt);
    fprintf(stderr, "%s: ", progname);
    if (in_name)
	fprintf(stderr, "%s: ", in_name);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);

    exit(1);
}

static void *xzalloc(size_t n)
{
    void *p = calloc(n, 1);
    if (!p)
	error("out of memory");
    return p;
}

/*************************************************************************
//
**************************************************************************/

int main(int argc, char *argv[])
{
    int r;
    int lazy;
    const int max_try_lazy = 5;
    const lzo_uint big = 65536L;	/* can result in very slow compression */
    const lzo_uint32 flags = 0x1;

    lzo_bytep in;
    lzo_bytep infile;
    lzo_uint in_len, infile_len, start, offset, soff;

    lzo_bytep out;
    lzo_uint out_bufsize;
    lzo_uint out_len = 0;
    lzo_uint outfile_len;

    lzo_bytep test;

    lzo_byte wrkmem[LZO1X_999_MEM_COMPRESS];

    lzo_uint best_len;
    int best_lazy = -1;

    lzo_uint orig_len;
    lzo_uint32 uncompressed_checksum;
    lzo_uint32 compressed_checksum;

    FILE *f;
    long l;

    struct prefix *prefix;

    progname = argv[0];
    if (argc != 3) {
	fprintf(stderr, "Usage: %s file output-file\n", progname);
	exit(1);
    }
    in_name = argv[1];
    if (argc > 2)
	out_name = argv[2];

/*
 * Step 1: initialize the LZO library
 */
    if (lzo_init() != LZO_E_OK)
	error("internal error - lzo_init() failed!");

/*
 * Step 3: open the input file
 */
    f = fopen(in_name, "rb");
    if (!f)
	error("cannot open file: %s", strerror(errno));

    fseek(f, 0, SEEK_END);
    l = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (l <= 0) {
	error("empty file", progname, in_name);
	fclose(f);
	exit(1);
    }
    infile_len = (lzo_uint) l;
    out_bufsize = infile_len + infile_len / 16 + 64 + 3 + 2048;

/*
 * Step 4: allocate compression buffers and read the file
 */
    infile = xzalloc(infile_len);
    out = xzalloc(out_bufsize);
    infile_len = fread(infile, 1, infile_len, f);
    fclose(f);

/*
 * Select the portion which is for compression...
 */
    prefix = (struct prefix *)infile;
    start = get_32(&prefix->pfx_start);
    offset = get_32(&prefix->pfx_compressed);
    in = infile + offset;
    in_len = infile_len - offset;
    best_len = in_len;

/*
 * Step 5: compute a checksum of the uncompressed data
 */
    uncompressed_checksum = lzo_adler32(0, NULL, 0);
    uncompressed_checksum = lzo_adler32(uncompressed_checksum, in, in_len);

/*
 * Step 6a: compress from `in' to `out' with LZO1X-999
 */
    for (lazy = 0; lazy <= max_try_lazy; lazy++) {
	out_len = out_bufsize;
	r = lzo1x_999_compress_internal(in, in_len, out, &out_len, wrkmem,
					NULL, 0, 0,
					lazy, big, big, big, big, flags);
	if (r != LZO_E_OK)
	    /* this should NEVER happen */
	    error("internal error - compression failed: %d", r);

	if (out_len < best_len) {
	    best_len = out_len;
	    best_lazy = lazy;
	}
    }

/*
 * Step 7: check if compressible
 */
    if (best_len >= in_len) {
	fprintf(stderr, "%s: %s: this file contains incompressible data.",
		progname, in_name);
	/* do it anyway */
    }

/*
 * Step 8: compress data again using the best compressor found
 */
    out_len = out_bufsize;
    r = lzo1x_999_compress_internal(in, in_len, out, &out_len, wrkmem,
				    NULL, 0, 0,
				    best_lazy, big, big, big, big, flags);
    assert(r == LZO_E_OK);
    assert(out_len == best_len);

/*
 * Step 9: optimize compressed data (compressed data is in `out' buffer)
 */
#if 1
    /* Optimization does not require any data in the buffer that will
     * hold the uncompressed data. To prove this, we clear the buffer.
     */
    memset(in, 0, in_len);
#endif

    orig_len = in_len;
    r = lzo1x_optimize(out, out_len, in, &orig_len, NULL);
    if (r != LZO_E_OK || orig_len != in_len) {
	/* this should NEVER happen */
	error("internal error - optimization failed: %d", r);
    }

/*
 * Step 10: compute a checksum of the compressed data
 */
    compressed_checksum = lzo_adler32(0, NULL, 0);
    compressed_checksum = lzo_adler32(compressed_checksum, out, out_len);

/*
 * Step 11: write compressed data to a file
 */
    /* Make sure we have up to 2048 bytes of zero after the output */
    memset(out + out_len, 0, 2048);

    outfile_len = out_len;

    soff = get_32(&prefix->pfx_cdatalen);
    set_32((uint32_t *) (infile + soff), out_len);

    soff = get_32(&prefix->pfx_checksum);
    if (soff) {
	/* ISOLINUX padding and checksumming */
	uint32_t csum = 0;
	unsigned int ptr;
	outfile_len =
	    ((offset - start + out_len + 2047) & ~2047) - (offset - start);
	for (ptr = 64; ptr < offset; ptr += 4)
	    csum += get_32((uint32_t *) (infile + ptr));
	for (ptr = 0; ptr < outfile_len; ptr += 4)
	    csum += get_32((uint32_t *) (out + ptr));

	set_32((uint32_t *) (infile + soff), offset - start + outfile_len);
	set_32((uint32_t *) (infile + soff + 4), csum);
    }

	/*
    if (offset+outfile_len > get_32(&prefix->pfx_maxlma))
	error("output too big (%lu, max %lu)",
	      (unsigned long)offset+outfile_len,
	      (unsigned long)get_32(&prefix->pfx_maxlma));
	      */

    f = fopen(out_name, "wb");
    if (!f)
	error("cannot open output file %s: %s", out_name, strerror(errno));

    if (fwrite(infile + start, 1, offset - start, f) != offset - start ||
	fwrite(out, 1, outfile_len, f) != outfile_len || fclose(f))
	error("write error");

/*
 * Step 12: verify decompression
 */
#ifdef PARANOID
    orig_len = in_len * 2;
    test = xzalloc(orig_len);
    r = lzo1x_decompress_safe(out, out_len, test, &orig_len, NULL);

    if (r != LZO_E_OK || orig_len != in_len) {
	/* this should NEVER happen */
	error("internal error - decompression failed: %d", r);
    }

    if (memcmp(test, in, in_len)) {
	/* this should NEVER happen */
	error("internal error - decompression data error");
    }

    /* Now you could also verify decompression under similar conditions as in
     * your application, e.g. overlapping assembler decompression etc.
     */

    free(test);
#endif

    free(infile);
    free(out);

    return 0;
}
