/*
 * unzip.c
 *
 * This is a collection of several routines from gzip-1.0.3
 * adapted for Linux.
 *
 * malloc by Hannu Savolainen 1993 and Matthias Urlichs 1994
 * puts by Nick Holloway 1993, better puts by Martin Mares 1995
 * High loaded stuff by Hans Lermen & Werner Almesberger, Feb. 1996
 *
 * Adapted for MEMDISK by H. Peter Anvin, April 2003
 */

#include <stdint.h>
#include "memdisk.h"
#include "conio.h"

#undef DEBUG			/* Means something different for this file */

/*
 * gzip declarations
 */

#define OF(args)  args
#define STATIC static

#define memzero(s, n)     memset ((s), 0, (n))

typedef uint8_t uch;
typedef uint16_t ush;
typedef uint32_t ulg;

#define WSIZE 0x8000		/* Window size must be at least 32k, */
				/* and a power of two */

static uch *inbuf;		/* input pointer */
static uch window[WSIZE];	/* sliding output window buffer */

static unsigned insize;		/* total input bytes read */
static unsigned inbytes;	/* valid bytes in inbuf */
static unsigned outcnt;		/* bytes in output buffer */

/* gzip flag byte */
#define ASCII_FLAG   0x01	/* bit 0 set: file probably ASCII text */
#define CONTINUATION 0x02	/* bit 1 set: continuation of multi-part gzip file */
#define EXTRA_FIELD  0x04	/* bit 2 set: extra field present */
#define ORIG_NAME    0x08	/* bit 3 set: original file name present */
#define COMMENT      0x10	/* bit 4 set: file comment present */
#define ENCRYPTED    0x20	/* bit 5 set: file is encrypted */
#define RESERVED     0xC0	/* bit 6,7:   reserved */

/* Diagnostic functions */
#ifdef DEBUG
#  define Assert(cond,msg) {if(!(cond)) error(msg);}
#  define Trace(x) fprintf x
#  define Tracev(x) {if (verbose) fprintf x ;}
#  define Tracevv(x) {if (verbose>1) fprintf x ;}
#  define Tracec(c,x) {if (verbose && (c)) fprintf x ;}
#  define Tracecv(c,x) {if (verbose>1 && (c)) fprintf x ;}
#else
#  define Assert(cond,msg)
#  define Trace(x)
#  define Tracev(x)
#  define Tracevv(x)
#  define Tracec(c,x)
#  define Tracecv(c,x)
#endif

static int fill_inbuf(void);
static void flush_window(void);
static void error(char *m);
static void gzip_mark(void **);
static void gzip_release(void **);

static ulg crc_32_tab[256];

/* Get byte from input buffer */
static inline uch get_byte(void)
{
    if (inbytes) {
	uch b = *inbuf++;
	inbytes--;
	return b;
    } else {
	return fill_inbuf();	/* Input buffer underrun */
    }
}

/* Unget byte from input buffer */
static inline void unget_byte(void)
{
    inbytes++;
    inbuf--;
}

static ulg bytes_out = 0;	/* Number of bytes output */
static uch *output_data;	/* Output data pointer */
static ulg output_size;		/* Number of output bytes expected */

static void *malloc(int size);
static void free(void *where);

static ulg free_mem_ptr, free_mem_end_ptr;

#include "inflate.c"

static void *malloc(int size)
{
    void *p;

    if (size < 0)
	error("malloc error");

    free_mem_ptr = (free_mem_ptr + 3) & ~3;	/* Align */

    p = (void *)free_mem_ptr;
    free_mem_ptr += size;

    if (free_mem_ptr >= free_mem_end_ptr)
	error("out of memory");

    return p;
}

static void free(void *where)
{
    /* Don't care */
    (void)where;
}

static void gzip_mark(void **ptr)
{
    *ptr = (void *)free_mem_ptr;
}

static void gzip_release(void **ptr)
{
    free_mem_ptr = (long)*ptr;
}

/* ===========================================================================
 * Fill the input buffer. This is called only when the buffer is empty
 * and at least one byte is really needed.
 */
static int fill_inbuf(void)
{
    /* This should never happen.  We have already pointed the algorithm
       to all the data we have. */
    die("failed\nDecompression error: ran out of input data\n");
}

/* ===========================================================================
 * Write the output window window[0..outcnt-1] and update crc and bytes_out.
 * (Used for the decompressed data only.)
 */
static void flush_window(void)
{
    ulg c = crc;		/* temporary variable */
    unsigned n;
    uch *in, *out, ch;

    if (bytes_out + outcnt > output_size)
	error("output buffer overrun");

    in = window;
    out = output_data;
    for (n = 0; n < outcnt; n++) {
	ch = *out++ = *in++;
	c = crc_32_tab[(c ^ ch) & 0xff] ^ (c >> 8);
    }
    crc = c;
    output_data = out;
    bytes_out += (ulg) outcnt;
    outcnt = 0;
}

static void error(char *x)
{
    die("failed\nDecompression error: %s\n", x);
}

/* GZIP header */
struct gzip_header {
    uint16_t magic;
    uint8_t method;
    uint8_t flags;
    uint32_t timestamp;
    uint8_t extra_flags;
    uint8_t os_type;
} __attribute__ ((packed));
/* (followed by optional and variable length "extra", "original name",
   and "comment" fields) */

struct gzip_trailer {
    uint32_t crc;
    uint32_t dbytes;
} __attribute__ ((packed));

/* PKZIP header.  See
 * <http://www.pkware.com/products/enterprise/white_papers/appnote.html>.
 */
struct pkzip_header {
    uint32_t magic;
    uint16_t version;
    uint16_t flags;
    uint16_t method;
    uint16_t modified_time;
    uint16_t modified_date;
    uint32_t crc;
    uint32_t zbytes;
    uint32_t dbytes;
    uint16_t filename_len;
    uint16_t extra_len;
} __attribute__ ((packed));
/* (followed by optional and variable length "filename" and "extra"
   fields) */

/* gzip flag byte */
#define ASCII_FLAG   0x01	/* bit 0 set: file probably ASCII text */
#define CONTINUATION 0x02	/* bit 1 set: continuation of multi-part gzip file */
#define EXTRA_FIELD  0x04	/* bit 2 set: extra field present */
#define ORIG_NAME    0x08	/* bit 3 set: original file name present */
#define COMMENT      0x10	/* bit 4 set: file comment present */
#define ENCRYPTED    0x20	/* bit 5 set: file is encrypted */
#define RESERVED     0xC0	/* bit 6,7:   reserved */

/* pkzip flag byte */
#define PK_ENCRYPTED     0x01	/* bit 0 set: file is encrypted */
#define PK_DATADESC       0x08	/* bit 3 set: file has trailing "data
				   descriptor" */
#define PK_UNSUPPORTED    0xFFF0	/* All other bits must be zero */

/* Return 0 if (indata, size) points to a ZIP file, and fill in
   compressed data size, uncompressed data size, CRC, and offset of
   data.

   If indata is not a ZIP file, return -1. */
int check_zip(void *indata, uint32_t size, uint32_t * zbytes_p,
	      uint32_t * dbytes_p, uint32_t * orig_crc, uint32_t * offset_p)
{
    struct gzip_header *gzh = (struct gzip_header *)indata;
    struct pkzip_header *pkzh = (struct pkzip_header *)indata;
    uint32_t offset;

    if (gzh->magic == 0x8b1f) {
	struct gzip_trailer *gzt = indata + size - sizeof(struct gzip_trailer);
	/* We only support method #8, DEFLATED */
	if (gzh->method != 8) {
	    error("gzip file uses invalid method");
	    return -1;
	}
	if (gzh->flags & ENCRYPTED) {
	    error("gzip file is encrypted; not supported");
	    return -1;
	}
	if (gzh->flags & CONTINUATION) {
	    error("gzip file is a continuation file; not supported");
	    return -1;
	}
	if (gzh->flags & RESERVED) {
	    error("gzip file has unsupported flags");
	    return -1;
	}
	offset = sizeof(*gzh);
	if (gzh->flags & EXTRA_FIELD) {
	    /* Skip extra field */
	    unsigned len = *(unsigned *)(indata + offset);
	    offset += 2 + len;
	}
	if (gzh->flags & ORIG_NAME) {
	    /* Discard the old name */
	    uint8_t *p = indata;
	    while (p[offset] != 0 && offset < size) {
		offset++;
	    }
	    offset++;
	}

	if (gzh->flags & COMMENT) {
	    /* Discard the comment */
	    uint8_t *p = indata;
	    while (p[offset] != 0 && offset < size) {
		offset++;
	    }
	    offset++;
	}

	if (offset > size) {
	    error("gzip file corrupt");
	    return -1;
	}
	*zbytes_p = size - offset - sizeof(struct gzip_trailer);
	*dbytes_p = gzt->dbytes;
	*orig_crc = gzt->crc;
	*offset_p = offset;
	return 0;
    } else if (pkzh->magic == 0x04034b50UL) {
	/* Magic number matches pkzip file. */

	offset = sizeof(*pkzh);
	if (pkzh->flags & PK_ENCRYPTED) {
	    error("pkzip file is encrypted; not supported");
	    return -1;
	}
	if (pkzh->flags & PK_DATADESC) {
	    error("pkzip file uses data_descriptor field; not supported");
	    return -1;
	}
	if (pkzh->flags & PK_UNSUPPORTED) {
	    error("pkzip file has unsupported flags");
	    return -1;
	}

	/* We only support method #8, DEFLATED */
	if (pkzh->method != 8) {
	    error("pkzip file uses invalid method");
	    return -1;
	}
	/* skip header */
	offset = sizeof(*pkzh);
	/* skip filename */
	offset += pkzh->filename_len;
	/* skip extra field */
	offset += pkzh->extra_len;

	if (offset + pkzh->zbytes > size) {
	    error("pkzip file corrupt");
	    return -1;
	}

	*zbytes_p = pkzh->zbytes;
	*dbytes_p = pkzh->dbytes;
	*orig_crc = pkzh->crc;
	*offset_p = offset;
	return 0;
    } else {
	/* Magic number does not match. */
	return -1;
    }

    error("Internal error in check_zip");
    return -1;
}

/*
 * Decompress the image, trying to flush the end of it as close
 * to end_mem as possible.  Return a pointer to the data block,
 * and change datalen.
 */
extern void _end;

static char heap[65536];

void *unzip(void *indata, uint32_t zbytes, uint32_t dbytes,
	    uint32_t orig_crc, void *target)
{
    /* Set up the heap; it is simply a chunk of bss memory */
    free_mem_ptr     = (size_t)heap;
    free_mem_end_ptr = (size_t)heap + sizeof heap;

    /* Set up input buffer */
    inbuf = indata;
    /* Sometimes inflate() looks beyond the end of the compressed data,
       but it always backs up before it is done.  So we give it 4 bytes
       of slack. */
    insize = inbytes = zbytes + 4;

    /* Set up output buffer */
    outcnt = 0;
    output_data = target;
    output_size = dbytes;
    bytes_out = 0;

    makecrc();
    gunzip();

    /* Verify that gunzip() consumed the entire input. */
    if (inbytes != 4)
	error("compressed data length error");

    /* Check the uncompressed data length and CRC. */
    if (bytes_out != dbytes)
	error("uncompressed data length error");

    if (orig_crc != CRC_VALUE)
	error("crc error");

    puts("ok\n");

    return target;
}
