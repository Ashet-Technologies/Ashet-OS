#include <stdlib.h>
#include <errno.h>
#include <string.h>
// #include <arpa/inet.h>
#include <netinet/in.h>

// #include "dhcp.h"
#include <dhcp.h>

/*
 * Pack DHCP options into an option field, without overload support.
 * On return, len contains the number of active bytes, and the full
 * field is zero-padded.
 *
 * Options which are successfully placed have their length zeroed out.
 */
static int dhcp_pack_field_zero(void *field, size_t *len,
				struct dhcp_option opt[256])
{
	int i;
	size_t xlen, plen;
	const uint8_t *p;
	uint8_t *q = field;
	size_t spc = *len;
	int err = 0;

	if (!*len)
		return ENOSPC;

	for (i = 1; i < 255; i++) {
		if (opt[i].len < 0)
			continue;

		/* We need to handle the 0 case as well as > 255 */
		if (opt[i].len <= 255)
			xlen = opt[i].len + 2;
		else
			xlen = opt[i].len + 2*((opt[i].len+254)/255);

		p = opt[i].data;

		if (xlen >= spc) {
			/* This option doesn't fit... */
			err++;
			continue;
		}

		xlen = opt[i].len;
		do {
			*q++ = i;
			*q++ = plen = xlen > 255 ? 255 : xlen;
			if (plen)
				memcpy(q, p, plen);
			q += plen;
			p += plen;
			spc -= plen+2;
			xlen -= plen;
		} while (xlen);

		opt[i].len = -1;
	}

	*q++ = 255;		/* End marker */
	memset(q, 0, spc);	/* Zero-pad the rest of the field */
	
	*len = xlen = q - (uint8_t *)field;
	return err;
}

/*
 * Pack DHCP options into an option field, without overload support.
 * On return, len contains the number of active bytes, and the full
 * field is zero-padded.
 *
 * Use this to encode encapsulated option fields.
 */
int dhcp_pack_field(void *field, size_t *len,
		    struct dhcp_option opt[256])
{
	struct dhcp_option ox[256];
	
	memcpy(ox, opt, sizeof ox);
	return dhcp_pack_field_zero(field, len, ox);
}

/*
 * Pack DHCP options into a packet.
 * Apply overloading if (and only if) the "file" or "sname" option
 * doesn't fit in the respective dedicated fields.
 */
int dhcp_pack_packet(void *packet, size_t *len,
		     const struct dhcp_option opt[256])
{
	struct dhcp_packet *pkt = packet;
	size_t spc = *len;
	uint8_t overload;
	struct dhcp_option ox[256];
	uint8_t *q;
	int err;

	if (spc < sizeof(struct dhcp_packet))
		return ENOSPC;	/* Buffer impossibly small */
	
	pkt->magic = htonl(DHCP_VENDOR_MAGIC);

	memcpy(ox, opt, sizeof ox);

	/* Figure out if we should do overloading or not */
	overload = 0;

	if (opt[67].len > 128)
		overload |= 1;
	else
		ox[67].len = -1;

	if (opt[66].len > 64)
		overload |= 2;
	else
		ox[66].len = -1;

	/* Kill any passed-in overload option */
	ox[52].len = -1;

	q = pkt->options;
	spc -= 240;

	/* Force option 53 (DHCP packet type) first */
	if (ox[53].len == 1) {
		*q++ = 53;
		*q++ = 1;
		*q++ = *(uint8_t *)ox[53].data;
		spc -= 3;
		ox[53].len = -1;
	}

	/* Follow with the overload option, if applicable */
	if (overload) {
		*q++ = 52;
		*q++ = 1;
		*q++ = overload;
		spc -= 3;
	}

	err = dhcp_pack_field_zero(q, &spc, ox);
	*len = spc + (q-(uint8_t *)packet);

	if (overload & 1) {
		spc = 128;
		err = dhcp_pack_field_zero(pkt->file, &spc, ox);
	} else {
		memset(pkt->file, 0, 128);
		if (opt[67].len > 0)
			memcpy(pkt->file, opt[67].data, opt[67].len);
	}

	if (overload & 2) {
		spc = 64;
		err = dhcp_pack_field_zero(pkt->sname, &spc, ox);
	} else {
		memset(pkt->sname, 0, 64);
		if (opt[66].len > 0)
			memcpy(pkt->sname, opt[66].data, opt[66].len);
	}

	return err;
}
