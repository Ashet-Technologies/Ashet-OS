/*
 * Compress input and feed it to a block-oriented back end.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <stdbool.h>
#include <zlib.h>
#include "upload_backend.h"
#include "ctime.h"

#define ALLOC_CHUNK	65536

int init_data(struct upload_backend *be, const char *argv[])
{
    be->now = posix_time();
    be->argv = argv;

    memset(&be->zstream, 0, sizeof be->zstream);

    be->zstream.next_out  = NULL;
    be->outbuf = NULL;
    be->zstream.avail_out = be->alloc  = 0;
    be->dbytes = be->zbytes = 0;

    /* Initialize a gzip data stream */
    if (deflateInit2(&be->zstream, 9, Z_DEFLATED,
		     16+15, 9, Z_DEFAULT_STRATEGY) < 0)
	return -1;

    return 0;
}

static int do_deflate(struct upload_backend *be, int flush)
{
    int rv;
    char *buf;

    while (1) {
	rv = deflate(&be->zstream, flush);
	be->zbytes = be->alloc - be->zstream.avail_out;
	if (be->zstream.avail_out)
	    return rv;		   /* Not an issue of output space... */

	buf = realloc(be->outbuf, be->alloc + ALLOC_CHUNK);
	if (!buf)
	    return Z_MEM_ERROR;
	be->outbuf = buf;
	be->alloc += ALLOC_CHUNK;
	be->zstream.next_out = (void *)(buf + be->zbytes);
	be->zstream.avail_out = be->alloc - be->zbytes;
    }
}


int write_data(struct upload_backend *be, const void *buf, size_t len)
{
    int rv = Z_OK;

    be->zstream.next_in = (void *)buf;
    be->zstream.avail_in = len;

    be->dbytes += len;

    while (be->zstream.avail_in) {
	rv = do_deflate(be, Z_NO_FLUSH);
	if (rv < 0) {
	    printf("do_deflate returned %d\n", rv);
	    return -1;
	}
    }
    return 0;
}

/* Output the data and shut down the stream */
int flush_data(struct upload_backend *be)
{
    int rv = Z_OK;
    int err=-1;

    while (rv != Z_STREAM_END) {
	rv = do_deflate(be, Z_FINISH);
	if (rv < 0)
	    return -1;
    }

//    printf("Uploading data, %u bytes... ", be->zbytes);

    if ((err=be->write(be)) != 0)
	return err;

    free(be->outbuf);
    be->outbuf = NULL;
    be->dbytes = be->zbytes = be->alloc = 0;

//    printf("done.\n");
    return 0;
}
