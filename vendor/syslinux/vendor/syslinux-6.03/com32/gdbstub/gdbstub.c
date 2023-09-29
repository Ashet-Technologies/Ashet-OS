/*
 * Copyright (C) 2008 Stefan Hajnoczi <stefanha@gmail.com>.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

/**
 * @file
 *
 * GDB stub for remote debugging
 *
 */

#include <stdlib.h>
#include <stdint.h>
#include "serial.h"

typedef uint32_t gdbreg_t;

enum {
    POSIX_EINVAL = 0x1c,	/* used to report bad arguments to GDB */
    SIZEOF_PAYLOAD = 256,	/* buffer size of GDB payload data */
    DR7_CLEAR = 0x00000400,	/* disable hardware breakpoints */
    DR6_CLEAR = 0xffff0ff0,	/* clear breakpoint status */
};

/* The register snapshot, this must be in sync with interrupt handler and the
 * GDB protocol. */
enum {
    GDBMACH_EAX,
    GDBMACH_ECX,
    GDBMACH_EDX,
    GDBMACH_EBX,
    GDBMACH_ESP,
    GDBMACH_EBP,
    GDBMACH_ESI,
    GDBMACH_EDI,
    GDBMACH_EIP,
    GDBMACH_EFLAGS,
    GDBMACH_CS,
    GDBMACH_SS,
    GDBMACH_DS,
    GDBMACH_ES,
    GDBMACH_FS,
    GDBMACH_GS,
    GDBMACH_NREGS,
    GDBMACH_SIZEOF_REGS = GDBMACH_NREGS * sizeof(gdbreg_t)
};

/* Breakpoint types */
enum {
    GDBMACH_BPMEM,
    GDBMACH_BPHW,
    GDBMACH_WATCH,
    GDBMACH_RWATCH,
    GDBMACH_AWATCH,
};

struct gdbstub {
    int exit_handler;		/* leave interrupt handler */

    int signo;
    gdbreg_t *regs;

    void (*parse) (struct gdbstub * stub, char ch);
    uint8_t cksum1;

    /* Buffer for payload data when parsing a packet.  Once the
     * packet has been received, this buffer is used to hold
     * the reply payload. */
    char buf[SIZEOF_PAYLOAD + 4];	/* $...PAYLOAD...#XX */
    char *payload;		/* start of payload */
    int len;			/* length of payload */
};

/** Hardware breakpoint, fields stored in x86 bit pattern form */
struct hwbp {
    int type;			/* type (1=write watchpoint, 3=access watchpoint) */
    unsigned long addr;		/* linear address */
    size_t len;			/* length (0=1-byte, 1=2-byte, 3=4-byte) */
    int enabled;
};

static struct hwbp hwbps[4];
static gdbreg_t dr7 = DR7_CLEAR;

static inline void gdbmach_set_pc(gdbreg_t * regs, gdbreg_t pc)
{
    regs[GDBMACH_EIP] = pc;
}

static inline void gdbmach_set_single_step(gdbreg_t * regs, int step)
{
    regs[GDBMACH_EFLAGS] &= ~(1 << 8);	/* Trace Flag (TF) */
    regs[GDBMACH_EFLAGS] |= (step << 8);
}

static inline void gdbmach_breakpoint(void)
{
    __asm__ __volatile__("int $3\n");
}

static struct hwbp *gdbmach_find_hwbp(int type, unsigned long addr, size_t len)
{
    struct hwbp *available = NULL;
    unsigned int i;
    for (i = 0; i < sizeof hwbps / sizeof hwbps[0]; i++) {
	if (hwbps[i].type == type && hwbps[i].addr == addr
	    && hwbps[i].len == len) {
	    return &hwbps[i];
	}
	if (!hwbps[i].enabled) {
	    available = &hwbps[i];
	}
    }
    return available;
}

static void gdbmach_commit_hwbp(struct hwbp *bp)
{
    int regnum = bp - hwbps;

    /* Set breakpoint address */
    switch (regnum) {
    case 0:
__asm__ __volatile__("movl %0, %%dr0\n": :"r"(bp->addr));
	break;
    case 1:
__asm__ __volatile__("movl %0, %%dr1\n": :"r"(bp->addr));
	break;
    case 2:
__asm__ __volatile__("movl %0, %%dr2\n": :"r"(bp->addr));
	break;
    case 3:
__asm__ __volatile__("movl %0, %%dr3\n": :"r"(bp->addr));
	break;
    }

    /* Set type */
    dr7 &= ~(0x3 << (16 + 4 * regnum));
    dr7 |= bp->type << (16 + 4 * regnum);

    /* Set length */
    dr7 &= ~(0x3 << (18 + 4 * regnum));
    dr7 |= bp->len << (18 + 4 * regnum);

    /* Set/clear local enable bit */
    dr7 &= ~(0x3 << 2 * regnum);
    dr7 |= bp->enabled << 2 * regnum;
}

int gdbmach_set_breakpoint(int type, unsigned long addr, size_t len, int enable)
{
    struct hwbp *bp;

    /* Check and convert breakpoint type to x86 type */
    switch (type) {
    case GDBMACH_WATCH:
	type = 0x1;
	break;
    case GDBMACH_AWATCH:
	type = 0x3;
	break;
    default:
	return 0;		/* unsupported breakpoint type */
    }

    /* Only lengths 1, 2, and 4 are supported */
    if (len != 2 && len != 4) {
	len = 1;
    }
    len--;			/* convert to x86 breakpoint length bit pattern */

    /* Set up the breakpoint */
    bp = gdbmach_find_hwbp(type, addr, len);
    if (!bp) {
	return 0;		/* ran out of hardware breakpoints */
    }
    bp->type = type;
    bp->addr = addr;
    bp->len = len;
    bp->enabled = enable;
    gdbmach_commit_hwbp(bp);
    return 1;
}

static void gdbmach_disable_hwbps(void)
{
    /* Store and clear hardware breakpoints */
    __asm__ __volatile__("movl %0, %%dr7\n"::"r"(DR7_CLEAR));
}

static void gdbmach_enable_hwbps(void)
{
    /* Clear breakpoint status register */
    __asm__ __volatile__("movl %0, %%dr6\n"::"r"(DR6_CLEAR));

    /* Restore hardware breakpoints */
    __asm__ __volatile__("movl %0, %%dr7\n"::"r"(dr7));
}

/* Packet parser states */
static void gdbstub_state_new(struct gdbstub *stub, char ch);
static void gdbstub_state_data(struct gdbstub *stub, char ch);
static void gdbstub_state_cksum1(struct gdbstub *stub, char ch);
static void gdbstub_state_cksum2(struct gdbstub *stub, char ch);
static void gdbstub_state_wait_ack(struct gdbstub *stub, char ch);

static void serial_write(void *buf, size_t len)
{
    char *p = buf;
    while (len-- > 0)
	serial_putc(*p++);
}

static uint8_t gdbstub_from_hex_digit(char ch)
{
    if (ch >= '0' && ch <= '9')
	return ch - '0';
    else if (ch >= 'A' && ch <= 'F')
	return ch - 'A' + 0xa;
    else
	return (ch - 'a' + 0xa) & 0xf;
}

static uint8_t gdbstub_to_hex_digit(uint8_t b)
{
    b &= 0xf;
    return (b < 0xa ? '0' : 'a' - 0xa) + b;
}

/*
 * To make reading/writing device memory atomic, we check for
 * 2- or 4-byte aligned operations and handle them specially.
 */

static void gdbstub_from_hex_buf(char *dst, char *src, int lenbytes)
{
    if (lenbytes == 2 && ((unsigned long)dst & 0x1) == 0) {
	uint16_t i = gdbstub_from_hex_digit(src[2]) << 12 |
	    gdbstub_from_hex_digit(src[3]) << 8 |
	    gdbstub_from_hex_digit(src[0]) << 4 |
	    gdbstub_from_hex_digit(src[1]);
	*(uint16_t *) dst = i;
    } else if (lenbytes == 4 && ((unsigned long)dst & 0x3) == 0) {
	uint32_t i = gdbstub_from_hex_digit(src[6]) << 28 |
	    gdbstub_from_hex_digit(src[7]) << 24 |
	    gdbstub_from_hex_digit(src[4]) << 20 |
	    gdbstub_from_hex_digit(src[5]) << 16 |
	    gdbstub_from_hex_digit(src[2]) << 12 |
	    gdbstub_from_hex_digit(src[3]) << 8 |
	    gdbstub_from_hex_digit(src[0]) << 4 |
	    gdbstub_from_hex_digit(src[1]);
	*(uint32_t *) dst = i;
    } else {
	while (lenbytes-- > 0) {
	    *dst++ = gdbstub_from_hex_digit(src[0]) << 4 |
		gdbstub_from_hex_digit(src[1]);
	    src += 2;
	}
    }
}

static void gdbstub_to_hex_buf(char *dst, char *src, int lenbytes)
{
    if (lenbytes == 2 && ((unsigned long)src & 0x1) == 0) {
	uint16_t i = *(uint16_t *) src;
	dst[0] = gdbstub_to_hex_digit(i >> 4);
	dst[1] = gdbstub_to_hex_digit(i);
	dst[2] = gdbstub_to_hex_digit(i >> 12);
	dst[3] = gdbstub_to_hex_digit(i >> 8);
    } else if (lenbytes == 4 && ((unsigned long)src & 0x3) == 0) {
	uint32_t i = *(uint32_t *) src;
	dst[0] = gdbstub_to_hex_digit(i >> 4);
	dst[1] = gdbstub_to_hex_digit(i);
	dst[2] = gdbstub_to_hex_digit(i >> 12);
	dst[3] = gdbstub_to_hex_digit(i >> 8);
	dst[4] = gdbstub_to_hex_digit(i >> 20);
	dst[5] = gdbstub_to_hex_digit(i >> 16);
	dst[6] = gdbstub_to_hex_digit(i >> 28);
	dst[7] = gdbstub_to_hex_digit(i >> 24);
    } else {
	while (lenbytes-- > 0) {
	    *dst++ = gdbstub_to_hex_digit(*src >> 4);
	    *dst++ = gdbstub_to_hex_digit(*src);
	    src++;
	}
    }
}

static uint8_t gdbstub_cksum(char *data, int len)
{
    uint8_t cksum = 0;
    while (len-- > 0) {
	cksum += (uint8_t) * data++;
    }
    return cksum;
}

static void gdbstub_tx_packet(struct gdbstub *stub)
{
    uint8_t cksum = gdbstub_cksum(stub->payload, stub->len);
    stub->buf[0] = '$';
    stub->buf[stub->len + 1] = '#';
    stub->buf[stub->len + 2] = gdbstub_to_hex_digit(cksum >> 4);
    stub->buf[stub->len + 3] = gdbstub_to_hex_digit(cksum);
    serial_write(stub->buf, stub->len + 4);
    stub->parse = gdbstub_state_wait_ack;
}

/* GDB commands */
static void gdbstub_send_ok(struct gdbstub *stub)
{
    stub->payload[0] = 'O';
    stub->payload[1] = 'K';
    stub->len = 2;
    gdbstub_tx_packet(stub);
}

static void gdbstub_send_num_packet(struct gdbstub *stub, char reply, int num)
{
    stub->payload[0] = reply;
    stub->payload[1] = gdbstub_to_hex_digit((char)num >> 4);
    stub->payload[2] = gdbstub_to_hex_digit((char)num);
    stub->len = 3;
    gdbstub_tx_packet(stub);
}

/* Format is arg1,arg2,...,argn:data where argn are hex integers and data is not an argument */
static int gdbstub_get_packet_args(struct gdbstub *stub, unsigned long *args,
				   int nargs, int *stop_idx)
{
    int i;
    char ch = 0;
    int argc = 0;
    unsigned long val = 0;
    for (i = 1; i < stub->len && argc < nargs; i++) {
	ch = stub->payload[i];
	if (ch == ':') {
	    break;
	} else if (ch == ',') {
	    args[argc++] = val;
	    val = 0;
	} else {
	    val = (val << 4) | gdbstub_from_hex_digit(ch);
	}
    }
    if (stop_idx) {
	*stop_idx = i;
    }
    if (argc < nargs) {
	args[argc++] = val;
    }
    return ((i == stub->len || ch == ':') && argc == nargs);
}

static void gdbstub_send_errno(struct gdbstub *stub, int errno)
{
    gdbstub_send_num_packet(stub, 'E', errno);
}

static void gdbstub_report_signal(struct gdbstub *stub)
{
    gdbstub_send_num_packet(stub, 'S', stub->signo);
}

static void gdbstub_read_regs(struct gdbstub *stub)
{
    gdbstub_to_hex_buf(stub->payload, (char *)stub->regs, GDBMACH_SIZEOF_REGS);
    stub->len = GDBMACH_SIZEOF_REGS * 2;
    gdbstub_tx_packet(stub);
}

static void gdbstub_write_regs(struct gdbstub *stub)
{
    if (stub->len != 1 + GDBMACH_SIZEOF_REGS * 2) {
	gdbstub_send_errno(stub, POSIX_EINVAL);
	return;
    }
    gdbstub_from_hex_buf((char *)stub->regs, &stub->payload[1],
			 GDBMACH_SIZEOF_REGS);
    gdbstub_send_ok(stub);
}

static void gdbstub_read_mem(struct gdbstub *stub)
{
    unsigned long args[2];
    if (!gdbstub_get_packet_args
	(stub, args, sizeof args / sizeof args[0], NULL)) {
	gdbstub_send_errno(stub, POSIX_EINVAL);
	return;
    }
    args[1] = (args[1] < SIZEOF_PAYLOAD / 2) ? args[1] : SIZEOF_PAYLOAD / 2;
    gdbstub_to_hex_buf(stub->payload, (char *)args[0], args[1]);
    stub->len = args[1] * 2;
    gdbstub_tx_packet(stub);
}

static void gdbstub_write_mem(struct gdbstub *stub)
{
    unsigned long args[2];
    int colon;
    if (!gdbstub_get_packet_args
	(stub, args, sizeof args / sizeof args[0], &colon) || colon >= stub->len
	|| stub->payload[colon] != ':' || (stub->len - colon - 1) % 2 != 0) {
	gdbstub_send_errno(stub, POSIX_EINVAL);
	return;
    }
    gdbstub_from_hex_buf((char *)args[0], &stub->payload[colon + 1],
			 (stub->len - colon - 1) / 2);
    gdbstub_send_ok(stub);
}

static void gdbstub_continue(struct gdbstub *stub, int single_step)
{
    gdbreg_t pc;
    if (stub->len > 1
	&& gdbstub_get_packet_args(stub, (unsigned long *)&pc, 1, NULL)) {
	gdbmach_set_pc(stub->regs, pc);
    }
    gdbmach_set_single_step(stub->regs, single_step);
    stub->exit_handler = 1;
    /* Reply will be sent when we hit the next breakpoint or interrupt */
}

static void gdbstub_breakpoint(struct gdbstub *stub)
{
    unsigned long args[3];
    int enable = stub->payload[0] == 'Z' ? 1 : 0;
    if (!gdbstub_get_packet_args
	(stub, args, sizeof args / sizeof args[0], NULL)) {
	gdbstub_send_errno(stub, POSIX_EINVAL);
	return;
    }
    if (gdbmach_set_breakpoint(args[0], args[1], args[2], enable)) {
	gdbstub_send_ok(stub);
    } else {
	/* Not supported */
	stub->len = 0;
	gdbstub_tx_packet(stub);
    }
}

static void gdbstub_rx_packet(struct gdbstub *stub)
{
    switch (stub->payload[0]) {
    case '?':
	gdbstub_report_signal(stub);
	break;
    case 'g':
	gdbstub_read_regs(stub);
	break;
    case 'G':
	gdbstub_write_regs(stub);
	break;
    case 'm':
	gdbstub_read_mem(stub);
	break;
    case 'M':
	gdbstub_write_mem(stub);
	break;
    case 'c':			/* Continue */
    case 'k':			/* Kill */
    case 's':			/* Step */
    case 'D':			/* Detach */
	gdbstub_continue(stub, stub->payload[0] == 's');
	if (stub->payload[0] == 'D') {
	    gdbstub_send_ok(stub);
	}
	break;
    case 'Z':			/* Insert breakpoint */
    case 'z':			/* Remove breakpoint */
	gdbstub_breakpoint(stub);
	break;
    default:
	stub->len = 0;
	gdbstub_tx_packet(stub);
	break;
    }
}

/* GDB packet parser */
static void gdbstub_state_new(struct gdbstub *stub, char ch)
{
    if (ch == '$') {
	stub->len = 0;
	stub->parse = gdbstub_state_data;
    }
}

static void gdbstub_state_data(struct gdbstub *stub, char ch)
{
    if (ch == '#') {
	stub->parse = gdbstub_state_cksum1;
    } else if (ch == '$') {
	stub->len = 0;		/* retry new packet */
    } else {
	/* If the length exceeds our buffer, let the checksum fail */
	if (stub->len < SIZEOF_PAYLOAD) {
	    stub->payload[stub->len++] = ch;
	}
    }
}

static void gdbstub_state_cksum1(struct gdbstub *stub, char ch)
{
    stub->cksum1 = gdbstub_from_hex_digit(ch) << 4;
    stub->parse = gdbstub_state_cksum2;
}

static void gdbstub_state_cksum2(struct gdbstub *stub, char ch)
{
    uint8_t their_cksum;
    uint8_t our_cksum;

    stub->parse = gdbstub_state_new;
    their_cksum = stub->cksum1 + gdbstub_from_hex_digit(ch);
    our_cksum = gdbstub_cksum(stub->payload, stub->len);

    if (their_cksum == our_cksum) {
	serial_write("+", 1);
	if (stub->len > 0) {
	    gdbstub_rx_packet(stub);
	}
    } else {
	serial_write("-", 1);
    }
}

static void gdbstub_state_wait_ack(struct gdbstub *stub, char ch)
{
    if (ch == '+') {
	stub->parse = gdbstub_state_new;
    } else {
	/* This retransmit is very aggressive but necessary to keep
	 * in sync with GDB. */
	gdbstub_tx_packet(stub);
    }
}

void gdbstub_handler(int signo, gdbreg_t * regs)
{
    struct gdbstub stub;

    gdbmach_disable_hwbps();

    stub.parse = gdbstub_state_new;
    stub.payload = &stub.buf[1];
    stub.signo = signo;
    stub.regs = regs;
    stub.exit_handler = 0;
    gdbstub_report_signal(&stub);
    while (!stub.exit_handler)
	stub.parse(&stub, serial_getc());

    gdbmach_enable_hwbps();
}
