#define _GNU_SOURCE		/* For strnlen() */
#include <stdlib.h>
#include <errno.h>
#include <string.h>
// #include <arpa/inet.h>
#include <netinet/in.h>

// #include "dhcp.h"
#include <dhcp.h>

/*
 * Unpack DHCP options from a field.  Assumes opt is pre-initalized
 * (to all zero in the common case.)
 */
int dhcp_unpack_field(const void *field, size_t len,
		      struct dhcp_option opt[256])
{
	const uint8_t *p = field;
	int err = 0;

	while (len > 1) {
		uint8_t op;
		size_t xlen;

		op = *p++; len--;
		if (op == 0)
			continue;
		else if (op == 255)
			break;
		
		xlen = *p++; len--;
		if (xlen > len)
			break;
		if (opt[op].len < 0)
			opt[op].len = 0;
		if (xlen) {
			opt[op].data = realloc(opt[op].data,
					       opt[op].len + xlen + 1);
			if (!opt[op].data) {
				err = ENOMEM;
				continue;
			}
			memcpy((char *)opt[op].data + opt[op].len, p, xlen);
			opt[op].len += xlen;
			/* Null-terminate as a courtesy to users */
			*((char *)opt[op].data + opt[op].len) = 0;
			p += xlen;
			len -= xlen;
		}
	}

	return err;
}

/*
 * Unpack a DHCP packet, with overload support.  Do not use this
 * to unpack an encapsulated option set.
 */
int dhcp_unpack_packet(const void *packet, size_t len,
		       struct dhcp_option opt[256])
{
	const struct dhcp_packet *pkt = packet;
	int err;
	uint8_t overload;
	int i;

	if (len < 240 || pkt->magic != htonl(DHCP_VENDOR_MAGIC))
		return EINVAL;	/* Bogus packet */
	
	for (i = 0; i < 256; i++) {
		opt[i].len = -1; /* Option not present */
		opt[i].data = NULL;
	}
	
	err = dhcp_unpack_field(pkt->options, len-240, opt);

	overload = 0;
	if (opt[52].len == 1) {
		overload = *(uint8_t *)opt[52].data;
		free(opt[52].data);
		opt[52].len = -1;
		opt[52].data = NULL;
	}

	if (overload & 1) {
		err |= dhcp_unpack_field(pkt->file, 128, opt);
	} else {
		opt[67].len  = strnlen((const char *)pkt->file, 128);
		if (opt[67].len) {
			opt[67].data = malloc(opt[67].len + 1);
			if (opt[67].data) {
				memcpy(opt[67].data, pkt->file, opt[67].len);
				*((char *)opt[67].data + opt[67].len) = 0;
			} else {
				err |= ENOMEM;
			}
		}
	}

	if (overload & 2) {
		err |= dhcp_unpack_field(pkt->sname, 64, opt);
	} else {
		opt[66].len  = strnlen((const char *)pkt->sname, 64);
		if (opt[66].len) {
			opt[66].data = malloc(opt[66].len + 1);
			if (opt[66].data) {
				memcpy(opt[66].data, pkt->file, opt[66].len);
				*((char *)opt[66].data + opt[66].len) = 0;
			} else {
				err |= ENOMEM;
			}
		}
	}

	return err;
}
