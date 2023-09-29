/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2010-2011 Gene Cumm
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * cptime.c	Version 1.4
 *
 * Timed copy; read entire file then output total time, bytes transferred,
 * and compute transfer rate.
 *
 * cptime [-s|-l] [-v|-q] [-b _SIZE_] [-n _LEN_] _FILE_...
 *	-s	Change to simple output mode without computing transfer rate
 *	-l	Change to long output mode (to allow for overriding previous -s)
 *	-v	Verbose output
 *	-q	Quiet output
 *	-b _SIZE_	use _SIZE_ for transfer size
 *	-n _LEN_	maximum length to fetch
 *	_FILE_...	Space delimited list of files to dump
 * Note: The last instance of -s or -l wins, along with the last use of -b and -n and the winning option will be applied to all operations
 *
 * Hisory:
 * 1.4	Use fread() rather than read(); use CLK_TCK when available.
 * 1.3	Added -v/-q; rework some argument processing.
 * 1.2	Added -n
 * 1.1	Added -l and -b switches; more flexible command line processing
 * 1.0	First release
 */

/*
 * ToDos:
 * - Refine timing to be more precise.  Low priority.
 * - Add -o for offset.  Wishlist.
 */

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/times.h>
#include <consoles.h>
#include <minmax.h>
#include <limits.h>
#include <string.h>
#include <stdint.h>
#include <console.h>

#ifdef __COM32__
#  define BUFSZ_DEF	(size_t)2048
/* What's optimal?  Under 4k?
 *	layout.inc: xfer_buf_seg	equ 1000h
 *	com32.inc: push dword (1 << 16)		; 64K bounce buffer
 */
/* typedef size_t off_t */

#  define TPS_T	float
#  ifdef CLK_TCK
static inline TPS_T get_tps(void) {	return CLK_TCK;	}
#  else
static inline TPS_T get_tps(void) {	return 18.2;	}
#  endif

#else /* __COM32__ */

#  define BUFSZ_DEF	(size_t)16384
/* Need to check what might be a "best" buffer/fetch block size here */

#  define TPS_T	long
static inline TPS_T get_tps(void) {	return sysconf(_SC_CLK_TCK);	}

#endif /* __COM32__ */

#ifndef SSIZE_MAX
#  define SSIZE_MAX	PTRDIFF_MAX
#endif
/* typedef ptrdiff_t ssize_t; */
#define BUFSZ_MAX	(size_t)SSIZE_MAX
/* ssize_t max */
#define BUFSZ_MIN	(size_t)1


/* Please note: I don't know the origin of these two macros nor their license */
#define TYPE_SIGNED(t) (! ((t) 0 < (t) -1))
#define TYPE_MAX(t) \
  ((t) (! TYPE_SIGNED (t) \
        ? (t) -1 \
	: ~ (~ (t) 0 << (sizeof (t) * CHAR_BIT - 1))))

#ifndef OFF_T_MAX
#  define OFF_T_MAX	TYPE_MAX(off_t)
#endif
/* Can't be SIZE_MAX or SSIZE_MAX as Syslinux/COM32 is unsigned while Linux 
 * is signed.
 */

#define LEN_MAX		OFF_T_MAX
/* off_t max */
#define LEN_MIN		(off_t)0

void print_cp_result_tick(size_t bcnt, clock_t et, TPS_T tps, int offs)
{
	size_t dr;
	/* prevent divide by 0 */
	dr = max(bcnt, (bcnt * tps)) / max((clock_t)1, (et + offs));
	printf("  %+d %zu B/s; %zu KiB/s; %zu MiB/s\n", offs, dr, dr/1024, dr/1048576);
}	/* void print_cp_result_tick(size_t bcnt, clock_t et, TPS_T tps, int offs) */

void print_cp_result_long(char *fn, size_t bcnt, clock_t bc, clock_t ec, size_t bufsz, char do_verbose)
{
	TPS_T tps;
	if (do_verbose > 2)
		printf("Enter print_cp_result_long()\n");
	tps = get_tps();
	printf("  %zu B in %d ticks from '%s'\n", bcnt, (int)(ec - bc), fn);
	printf("  ~%d ticks per second; %zu B block/transfer size\n", (int)tps, bufsz);
	print_cp_result_tick(bcnt, (ec - bc), tps, 0);
	print_cp_result_tick(bcnt, (ec - bc), tps, 1);
	print_cp_result_tick(bcnt, (ec - bc), tps, -1);
}	/* void print_cp_result_long(char *fn, size_t bcnt, clock_t bc, clock_t ec, size_t bufsz) */

void print_cp_result_simple(char *fn, size_t bcnt, clock_t bc, clock_t ec, size_t bufsz, char do_verbose)
{
	if (do_verbose) {}
	printf("  %zuB  %dt %zux '%s'\n", bcnt, (int)(ec - bc), bufsz, fn);
}	/* void print_cp_result_simple(char *fn, int bcnt, clock_t bc, clock_t ec, char do_verbose) */

size_t time_copy_bufsz(size_t bufsz, size_t bcnt, off_t maxlen)
{
	return min(bufsz, (maxlen - bcnt));
}	/* size_t time_copy_bufsz(size_t bufsz, size_t bcnt, off_t maxlen) */

int time_copy(char *fn, char do_simple, char do_verbose, size_t ibufsz, off_t maxlen)
{
// 	int fd;
	int rv = 0;
	int i = 0;
	FILE *f;
	size_t bufsz, bcnt = 0;
	int numrd;
	struct tms tm;
	clock_t bc, ec;
	char buf[ibufsz + 1];

	buf[0] = 0;
	if (do_verbose)
		printf("Trying file '%s'\n", fn);
	errno = 0;
// 	fd = open(fn, O_RDONLY);
	f = fopen(fn, "r");
// 	if (fd == -1) {
	if (!f) {
		switch (errno) {
		case ENOENT :
			printf("File '%s' does not exist\n", fn);
			break;
		case EBADF:
			printf("File '%s': Bad File Descriptor\n", fn);
			break;
		default :
			printf("Error '%d' opening file '%s'\n", errno, fn);
		}
		rv = 1;
	} else {
		if (do_verbose)
			printf("File '%s' opened\n", fn);
		bufsz = time_copy_bufsz(ibufsz, bcnt, maxlen);
		bc = times(&tm);
// 		numrd = read(fd, buf, bufsz);
// 		numrd = fread(buf, bufsz, 1, f);
		numrd = fread(buf, 1, bufsz, f);
		i++;
		if (numrd > 0)
			bcnt = numrd;
		while ((numrd > 0) && (bufsz > 0)) {
			bufsz = time_copy_bufsz(bufsz, bcnt, maxlen);
// 			numrd = read(fd, buf, bufsz);
// 			numrd = fread(buf, bufsz, 1, f);
			numrd = fread(buf, 1, bufsz, f);
			i++;
			if (numrd >= 0)
// 				bcnt = bcnt + numrd;
				bcnt += numrd;
		}
		ec = times(&tm);
// 		close(fd);
		fclose(f);
		if (do_verbose)
			printf("File '%s' closed\n", fn);
		if (numrd < 0) {
			switch (errno) {
			case EIO :
				printf("IO Error at %zu B reading file '%s'\n", bcnt, fn);
				break;
			case EINVAL :
				printf("Invalid Mode at %zu B reading file '%s'\n", bcnt, fn);
				break;
			default :
				printf("Error '%d' at %zu B reading file '%s'\n", errno, bcnt, fn);
			}
			rv = 2;
		}
		if (bcnt > 0) {
			if (bufsz == 0)
				printf("maxed out on maxln\n");
			if (do_simple)
				print_cp_result_simple(fn, bcnt, bc, ec, ibufsz, do_verbose);
			else
				print_cp_result_long(fn, bcnt, bc, ec, ibufsz, do_verbose);
		}
		if (do_verbose)
			printf("  numrd %d bcnt %d bufsz %d i %d\n", numrd, bcnt, bufsz, i);
	}
	return rv;
}	/* int time_copy(char *fn, char do_simple, int bufsz, off_t maxlen) */

int main(int argc, char *argv[])
{
	int i;
	char do_simple = 0, do_pbuf = 0, do_plen = 0, do_verbose = 0;
	char *arg;
	size_t tbufsz, bufsz = min((BUFSZ_DEF), (BUFSZ_MAX));
	off_t tmaxlen, maxlen = LEN_MAX;
	int numfl = 0;
	console_ansi_std();
// 	openconsole(&dev_stdcon_r, &dev_stdcon_w);
	for (i = 1; i < argc; i++) {
		if (argv[i][0] == '-') {
			arg = argv[i] + 1;
			if (strcmp(arg, "b") == 0) {
				i++;
				if (i < argc) {
					tbufsz = atoi(argv[i]);
					if (tbufsz > 0)
						bufsz = min(max((BUFSZ_MIN), tbufsz), (BUFSZ_MAX));
					do_pbuf = 1;
				}
			} else if (strcmp(arg, "n") == 0) {
				i++;
				if (i < argc) {
					tmaxlen = atoi(argv[i]);
					if (tmaxlen > 0)
						maxlen = min(max((LEN_MIN), tmaxlen), (LEN_MAX));
					do_plen = 1;
				}
			} else if (strcmp(arg, "s") == 0)
				do_simple = 1;
			else if (strcmp(arg, "l") == 0)
				do_simple = 0;
			else if (strcmp(arg, "v") == 0)
				do_verbose = 1;
			else if (strcmp(arg, "q") == 0)
				do_verbose = 0;
		}
	}
	if (do_pbuf || do_verbose)
		printf("Using bufsz %zu\n", bufsz);
	if (do_plen || do_verbose)
		printf("Using maxlen %zu\n", maxlen);
	for (i = 1; i < argc; i++) {
		if (argv[i][0] == '-') {
			arg = argv[i] + 1;
			if ((strcmp(arg, "b") == 0) || (strcmp(arg, "n") == 0))
				i++; 	/* Skip next arg */
			else if (!((strcmp(arg, "s") == 0) || (strcmp(arg, "l") == 0) || (strcmp(arg, "v") == 0) || (strcmp(arg, "q") == 0))) {
				time_copy(argv[i], do_simple, do_verbose, bufsz, maxlen);
				numfl++;
			}
		} else {
			time_copy(argv[i], do_simple, do_verbose, bufsz, maxlen);
			numfl++;
		}
	}
	if (numfl == 0)
		fprintf(stderr, "%s: Please specify a file\n", argv[0]);
	return 0;
}	/* int main(int argc, char *argv[]) */
