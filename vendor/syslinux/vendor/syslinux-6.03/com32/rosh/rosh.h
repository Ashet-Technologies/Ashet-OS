/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2008-2009 Gene Cumm - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * rosh.h
 *
 * Read-Only shell; Header
 */

/*
 * History
 * b034	Improve debug functions to simpler code
 * b021	Move much PreProcessing stuff to rosh.h
 * b018	Create rosh_debug() macro
 * b012	Version of rosh.c at time of creating this file.
 */

#ifndef ROSH_H
#define ROSH_H

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>		/* macro: true false */
#include <string.h>		/* strcpy() strlen() memcpy() strchr() */
#include <sys/types.h>
#include <limits.h>
#include <sys/stat.h>		/* fstat() */
#include <fcntl.h>		/* open(); open mode macros */
#include <dirent.h>		/* fdopendir() opendir() readdir() closedir() DIR */
#include <unistd.h>		/* getcwd() getopt() */
#include <errno.h>		/* errno; error macros */
#include <netinet/in.h>		/* For htonl/ntohl/htons/ntohs */
#include <ctype.h>		/* isspace() */

#include <getkey.h>
#include <consoles.h>		/* console_ansi_raw() console_ansi_std() */
// #include <getopt.h>		/* getopt_long() */

#ifdef DO_DEBUG
# define ROSH_DEBUG	printf
# define ROSH_DEBUG_ARGV_V	rosh_pr_argv_v
/* define ROSH_DEBUG(f, ...)	printf (f, ## __VA_ARGS__) */
# ifdef DO_DEBUG2
#  define ROSH_DEBUG2	printf
#  define ROSH_DEBUG2_ARGV_V	rosh_pr_argv_v
# else /* DO_DEBUG2 */
	/* This forces a format argument into the function call */
#  define ROSH_DEBUG2(f, ...)	((void)0)
#  define ROSH_DEBUG2_ARGV_V(argc, argv)	((void)0)
# endif	/* DO_DEBUG2 */
#else /* DO_DEBUG */
# define ROSH_DEBUG(f, ...)	((void)0)
# define ROSH_DEBUG_ARGV_V(argc, argv)	((void)0)
# define ROSH_DEBUG2(f, ...)	((void)0)
# define ROSH_DEBUG2_ARGV_V(argc, argv)	((void)0)
#endif /* DO_DEBUG */
#define ROSH_DEBUG2_STAT(f, ...)	((void)0)
// #define ROSH_DEBUG2_STAT	ROSH_DEBUG2

#ifdef __COM32__
#define ROSH_IS_COM32	1
#include <console.h>		/* openconsole() */
#include <syslinux/config.h>	/* Has info on the SYSLINUX variant */
#include <syslinux/boot.h>	/* syslinux_run_command() */
#include <syslinux/reboot.h>
#define ROSH_COM32(f, ...)	printf (f, ## __VA_ARGS__)
#define rosh_console_std()		console_ansi_std()
#define rosh_console_raw()		console_ansi_raw()

int stat(const char *pathname, struct stat *buf)
{
    int fd, status, ret = -1;
    DIR *d;

    ROSH_DEBUG2_STAT("stat:opendir(%s) ", pathname);
    d = opendir(pathname);
    if (d != NULL) {
	ROSH_DEBUG2_STAT("stat:closedir() ");
	closedir(d);
	ret = 0;
	buf->st_mode = S_IFDIR | 0555;
	buf->st_size = 0;
    } else if ((errno == 0) || (errno == ENOENT) || (errno == ENOTDIR)) {
	ROSH_DEBUG2_STAT("(%d)stat:open() ", errno);
	fd = open(pathname, O_RDONLY);
	if (fd != -1) {
	    ROSH_DEBUG2_STAT("(%d)stat:fstat() ", fd);
	    status = fstat(fd, buf);
	    (void)status;
	    ROSH_DEBUG2_STAT("stat:close() ");
	    close(fd);
	    ret = 0;
	}
    }
    return ret;
}

int rosh_get_env_ver(char *dest, size_t n)
{
    const struct syslinux_version *slv = syslinux_version();
    strncpy(dest, slv->version_string, n);
    return 0;
}

#else
#  include <termios.h>
#  include <sys/ioctl.h>
#  include <sys/utsname.h>
#  define ROSH_IS_COM32	0

static inline char *syslinux_config_file(void)
{
    return "";
}

int rosh_get_env_ver(char *dest, size_t n)
{
    int ret, len;
    struct utsname env;
    ret= uname(&env);
    if (ret >= 0) {
	strncpy(dest, env.sysname, n);
	len = strlen(dest);
	strncpy(dest + len, " ", (n - len));
	len = strlen(dest);
	strncpy(dest + len, env.release, (n - len));
    }
    return ret;
}

static inline int getscreensize(int fd, int *rows, int *cols)
{
    char *str;
    int rv;
    struct winsize ws;
    if (rows)
	*rows = 0;
    if (cols)
	*cols = 0;
    str = NULL;
    if (fd == 1) {
	ioctl(0, TIOCGWINSZ, &ws);
	if (rows)
	    *rows = ws.ws_row;
	if (cols)
	    *cols = ws.ws_col;
	if (rows && !*rows) {
	    str = getenv("LINES");
	    if (str)
		*rows = atoi(str);
	}
	if (cols && !*cols) {
	    str = getenv("COLUMNS");
	    if (str)
		*cols = atoi(str);
	}
    }
    if (!rows || !cols)
	rv = -1;
    else if (!*rows || !*cols)
	rv = -2;
    else
	rv = 0;
    return rv;
}

/*
 * Switches console over to raw input mode.  Allows get_key to get just
 * 1 key sequence (without delay or display)
 */
void rosh_console_raw(void)
{
    struct termios tio;

    console_ansi_raw();		/* Allows get_key to get just 1 key sequence
				   (w/o delay or display */
    /* Deal with the changes that haven't been replicated to ansiraw.c */
    tcgetattr(0, &tio);
    tio.c_iflag &= ~IGNCR;
    tcsetattr(0, TCSAFLUSH, &tio);
}

/*
 * Switches back to standard getline mode.
 */
void rosh_console_std(void)
{
    struct termios tio;

    console_ansi_std();
    tcgetattr(0, &tio);
    tio.c_iflag |= ICRNL;
    tio.c_iflag &= ~IGNCR;
    tcsetattr(0, TCSANOW, &tio);
}

void syslinux_reboot(int warm)
{
    printf("Test Reboot(%d)\n", warm);
}

#define ROSH_COM32(f, ...)	((void)0)
#define syslinux_run_command(f)	((void)0)
#endif /* __COM32__ */

#define SEP	'/'

/* Size of buffer string */
#define ROSH_BUF_SZ	16384
/* Size of screen output buffer (80*40) //HERE */
#define ROSH_SBUF_SZ	((80 + 2) * 40)

/* Size of command buffer string */
#ifdef MAX_CMDLINE_LEN
#  define ROSH_CMD_SZ		MAX_CMDLINE_LEN
#elif COMMAND_LINE_SIZE
#  define ROSH_CMD_SZ		COMMAND_LINE_SIZE
#else
#  define ROSH_CMD_SZ_LG2	12
#  define ROSH_CMD_SZ		(1 << ROSH_CMD_SZ_LG2)
#endif /* MAX_CMDLINE_LEN */

/* Size of path buffer string */
#ifdef PATH_MAX
#  define ROSH_PATH_SZ		PATH_MAX
#elif NAME_MAX
#  define ROSH_PATH_SZ		NAME_MAX
#elif FILENAME_MAX
#  define ROSH_PATH_SZ		FILENAME_MAX
#else
#  define ROSH_PATH_SZ_LG2	8
#  define ROSH_PATH_SZ		(1 << ROSH_PATH_SZ_LG2)
#endif /* PATH_MAX */

#define ROSH_OPT_SZ	8

const char rosh_beta_str[] =
    "  ROSH is currently beta.  Constructive feedback is appreciated";

const char rosh_cd_norun_str[] =
    " -- cd (Change Directory) not implemented for use with run and exit.\n";

const char rosh_help_cd_str[] = "cd    Change directory\n\
   with no argument, return to original directory from entry to rosh\n\
   with one argument, change to that directory";

const char rosh_help_ls_str[] = "ls    List contents of current directory\n\
  -l  Long format\n\
  -i  Inode; print Inode of file\n\
  -F  Classify; Add a 1-character suffix to classify files";

const char rosh_help_str1[] =
    "Commands: ? cat cd cfg dir exit help less ls man more pwd run quit ver";

const char rosh_help_str2[] =
    "Commands: (short generally non-ambiguous abreviations are also allowed)\n\
  h     HELP\n     ALSO ? help man\n     ALSO help <command>\n\
  cat   Concatenate file to console\n    cat <file>\n\
  cd    Change to directory <dir>\n    cd <dir>\n\
  less  Page a file with rewind\n\
  ls    List contents of current directory\n    ls <dir>\n\
    ALSO l dir\n\
  more  Page a file\n\
  pwd   display Present Working Directory\n\
  run   Run a program/kernel with options\n\
  r     Reboot (if COM32)\n        Also reboot\n\
  exit  Exit to previous environment\n    ALSO quit";

const char rosh_help_str_adv[] = "No additional help available for '%s'";

const char rosh_ls_opt_str[] = "lFi";

#endif /* Not ROSH_H */
