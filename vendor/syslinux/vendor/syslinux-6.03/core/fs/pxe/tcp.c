/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2011 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * tcp.c
 *
 * Common operations for TCP-based network protocols
 */

#include "pxe.h"
#include "net.h"

const struct pxe_conn_ops tcp_conn_ops = {
    .fill_buffer	= core_tcp_fill_buffer,
    .close		= core_tcp_close_file,
};
