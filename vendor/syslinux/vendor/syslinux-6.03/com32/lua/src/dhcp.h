/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2007 H. Peter Anvin - All Rights Reserved
 *   Copyright 2011 Timothy J Gleason <timmgleason_at_gmail.com> - All Rights Reserved
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

#include <stdint.h>

typedef struct dhcp {
  uint8_t	op;			/* message opcode */
  uint8_t	htype;			/* Hardware address type */
  uint8_t	hlen;			/* Hardware address length */
  uint8_t	hops;			/* Used by relay agents */
  uint32_t	xid;			/* transaction id */
  uint16_t	secs;			/* Secs elapsed since client boot */
  uint16_t	flags;			/* DHCP Flags field */
  uint8_t	ciaddr[4];		/* client IP addr */
  uint8_t	yiaddr[4];		/* 'Your' IP addr. (from server) */
  uint8_t	siaddr[4];		/* Boot server IP addr */
  uint8_t	giaddr[4];		/* Relay agent IP addr */
  uint8_t	chaddr[16];		/* Client hardware addr */
  uint8_t	sname[64];		/* Optl. boot server hostname */
  uint8_t	file[128];		/* boot file name (ascii path) */
  uint8_t	cookie[4];		/* Magic cookie */
  uint8_t	options[1020];		/* Options */
} dhcp_t;

