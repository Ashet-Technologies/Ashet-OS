/* -----------------------------------------------------------------------
 *
 *   Copyright 1999-2008 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2011 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * tftp.h
 */
#ifndef PXE_TFTP_H
#define PXE_TFTP_H

/*
 * TFTP default port number
 */
#define TFTP_PORT	 69

/*
 * TFTP default block size
 */
#define TFTP_BLOCKSIZE_LG2 9
#define TFTP_BLOCKSIZE  (1 << TFTP_BLOCKSIZE_LG2)

/*
 * TFTP operation codes
 */
#define TFTP_RRQ	 htons(1)		// Read rest
#define TFTP_WRQ	 htons(2)		// Write rest
#define TFTP_DATA	 htons(3)		// Data packet
#define TFTP_ACK	 htons(4)		// ACK packet
#define TFTP_ERROR	 htons(5)		// ERROR packet
#define TFTP_OACK	 htons(6)		// OACK packet

/*
 * TFTP error codes
 */
#define TFTP_EUNDEF	 htons(0)		// Unspecified error
#define TFTP_ENOTFOUND	 htons(1)		// File not found
#define TFTP_EACCESS	 htons(2)		// Access violation
#define TFTP_ENOSPACE	 htons(3)		// Disk full
#define TFTP_EBADOP	 htons(4)		// Invalid TFTP operation
#define TFTP_EBADID	 htons(5)		// Unknown transfer
#define TFTP_EEXISTS	 htons(6)		// File exists
#define TFTP_ENOUSER	 htons(7)		// No such user
#define TFTP_EOPTNEG	 htons(8)		// Option negotiation failure

#endif /* PXE_TFTP_H */
