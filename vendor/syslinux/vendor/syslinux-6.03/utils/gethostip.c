/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2001-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * gethostip.c
 *
 * Small program to use gethostbyname() to print out a hostname in
 * hex and/or dotted-quad notation
 */

#include <stdio.h>
#include <stdlib.h>
#include <netdb.h>
#include <sys/socket.h>
#include <unistd.h>
#include <sysexits.h>
#define _GNU_SOURCE		/* For getopt_long */
#include <getopt.h>

const struct option options[] = {
    {"hexadecimal", 0, NULL, 'x'},
    {"decimal", 0, NULL, 'd'},
    {"dotted-quad", 0, NULL, 'd'},
    {"full-output", 0, NULL, 'f'},
    {"name", 0, NULL, 'n'},
    {"help", 0, NULL, 'h'},
    {NULL, 0, NULL, 0}
};

const char *program;

void usage(int exit_code)
{
    fprintf(stderr, "Usage: %s [-dxnf] hostname/ip...\n", program);
    exit(exit_code);
}

int main(int argc, char *argv[])
{
    int opt;
    int output = 0;
    int i;
    char *sep;
    int err = 0;

    struct hostent *host;

    program = argv[0];

    while ((opt = getopt_long(argc, argv, "dxfnh", options, NULL)) != -1) {
	switch (opt) {
	case 'd':
	    output |= 2;	/* Decimal output */
	    break;
	case 'x':
	    output |= 4;	/* Hexadecimal output */
	    break;
	case 'n':
	    output |= 1;	/* Canonical name output */
	    break;
	case 'f':
	    output = 7;		/* Full output */
	    break;
	case 'h':
	    usage(0);
	    break;
	default:
	    usage(EX_USAGE);
	    break;
	}
    }

    if (optind == argc)
	usage(EX_USAGE);

    if (output == 0)
	output = 7;		/* Default output */

    for (i = optind; i < argc; i++) {
	sep = "";
	host = gethostbyname(argv[i]);
	if (!host) {
	    herror(argv[i]);
	    err = 1;
	    continue;
	}

	if (host->h_addrtype != AF_INET || host->h_length != 4) {
	    fprintf(stderr, "%s: No IPv4 address associated with name\n",
		    argv[i]);
	    err = 1;
	    continue;
	}

	if (output & 1) {
	    printf("%s%s", sep, host->h_name);
	    sep = " ";
	}

	if (output & 2) {
	    printf("%s%u.%u.%u.%u", sep,
		   ((unsigned char *)host->h_addr)[0],
		   ((unsigned char *)host->h_addr)[1],
		   ((unsigned char *)host->h_addr)[2],
		   ((unsigned char *)host->h_addr)[3]);
	    sep = " ";
	}

	if (output & 4) {
	    printf("%s%02X%02X%02X%02X", sep,
		   ((unsigned char *)host->h_addr)[0],
		   ((unsigned char *)host->h_addr)[1],
		   ((unsigned char *)host->h_addr)[2],
		   ((unsigned char *)host->h_addr)[3]);
	    sep = " ";
	}

	putchar('\n');
    }

    return err;
}
