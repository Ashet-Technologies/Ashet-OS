#ifndef _GETOPT_H
#define _GETOPT_H

/* (Very slightly) adapted from klibc */

struct option {
	const char *name;
	int has_arg;
	int *flag;
	int val;
};

enum {
	no_argument	  = 0,
	required_argument = 1,
	optional_argument = 2,
};

extern char *optarg;
extern int optind, opterr, optopt;

extern int getopt_long(int, char *const *, const char *,
			 const struct option *, int *);

#endif /* _GETOPT_H */
