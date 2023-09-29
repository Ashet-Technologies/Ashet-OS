/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2008-2011 Gene Cumm - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * rosh.c
 *
 * Read-Only shell; Simple shell system designed for SYSLINUX-derivitives.
 * Provides minimal commands utilizing the console via stdout/stderr as the
 * sole output devices.  Designed to compile for Linux for testing/debugging.
 */

/*
 * ToDos:
 * prompt:	Allow left/right arrow, home/end and more?
 * commands	Break into argv/argc-like array
 * rosh_cfg:	allow -s <file> to change config
 * rosh_ls():	sorted; then multiple columns
 * prompt:	Possibly honor timeout on initial entry for usage as UI
 *		Also possibly honor totaltimeout
 */

/*#define DO_DEBUG 1
//*/
/* Uncomment the above line for debugging output; Comment to remove */
/*#define DO_DEBUG2 1
//*/
/* Uncomment the above line for super-debugging output; Must have regular
 * debugging enabled; Comment to remove.
 */
#include "rosh.h"
#include "version.h"

#define APP_LONGNAME	"Read-Only Shell"
#define APP_NAME	"rosh"
#define APP_AUTHOR	"Gene Cumm"
#define APP_YEAR	"2010"
#define APP_VER		"beta-b090"

/* Print version information to stdout
 */
void rosh_version(int vtype)
{
    char env[256];
    env[0] = 0;
    printf("%s v %s; (c) %s %s.\n\tFrom Syslinux %s, %s\n", APP_LONGNAME, APP_VER, APP_YEAR, APP_AUTHOR, VERSION_STR, DATE);
    switch (vtype) {
    case 1:
	rosh_get_env_ver(env, 256);
	printf("\tRunning on %s\n", env);
    }
}

/* Print beta message and if DO_DEBUG/DO_DEBUG2 are active
 */
void print_beta(void)
{
    puts(rosh_beta_str);
    ROSH_DEBUG("DO_DEBUG active\n");
    ROSH_DEBUG2("DO_DEBUG2 active\n");
}

/* Search a string for first non-space (' ') character, starting at ipos
 *	istr	input string to parse
 *	ipos	input position to start at
 */
int rosh_search_nonsp(const char *istr, const int ipos)
{
    int curpos;
    char c;

    curpos = ipos;
    c = istr[curpos];
    while (c && isspace(c))
	c = istr[++curpos];
    return curpos;
}

/* Search a string for space (' '), returning the position of the next space
 * or the '\0' at end of string
 *	istr	input string to parse
 *	ipos	input position to start at
 */
int rosh_search_sp(const char *istr, const int ipos)
{
    int curpos;
    char c;

    curpos = ipos;
    c = istr[curpos];
    while (c && !(isspace(c)))
	c = istr[++curpos];
    return curpos;
}

/* Parse a string for the first non-space string, returning the end position
 * from src
 *	dest	string to contain the first non-space string
 *	src	string to parse
 *	ipos	Position to start in src
 */
int rosh_parse_sp_1(char *dest, const char *src, const int ipos)
{
    int bpos, epos;		/* beginning and ending position of source string
				   to copy to destination string */

    bpos = 0;
    epos = 0;
/* //HERE-error condition checking */
    bpos = rosh_search_nonsp(src, ipos);
    epos = rosh_search_sp(src, bpos);
    if (epos > bpos) {
	memcpy(dest, src + bpos, epos - bpos);
	if (dest[epos - bpos] != 0)
	    dest[epos - bpos] = 0;
    } else {
	epos = strlen(src);
	dest[0] = 0;
    }
    return epos;
}

/*
 * parse_args1: Try 1 at parsing a string to an argc/argv pair.  use free_args1 to free memory malloc'd
 *
 * Derived from com32/lib/sys/argv.c:__parse_argv()
 *   Copyright 2004-2009 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author: H. Peter Anvin
 */
int parse_args1(char ***iargv, const char *istr)
{
    int argc  = 0;
    const char *p;
    char *q, *r, *args, **arg;
    int sp = 1;	//, qt = 0;		/* Was a space; inside a quote */

    /* Scan 1: Length */
    /* I could eliminate this if I knew a max length, like strncpy() */
    int len = strlen(istr);

    /* Scan 2: Copy, nullify and make argc */
    if (!(args = malloc(len + 1)))
	goto fail_args;
    q = args;
    for (p = istr;; p++) {
	if (*p <= ' ') {
	    if (!sp) {
		sp = 1;
		*q++ = '\0';
	    }
	} else {
	    if (sp) {
		argc++;
		sp = 0;
	    }
	    *q++ = *p;
	}
	if (!*p)
	    break;
    }

    q--;			/* Point q to final null */
    /* Scan 3: Build array of pointers */
    if (!(*iargv = malloc((argc + 1) * sizeof(char *))))
	goto fail_args_ptr;
    arg = *iargv;
    arg[argc] = NULL;		/* Nullify the last pointer */
    if (*args != '\0')
	    *arg++ = args;
    for (r = args; r < q ; r++) {
	if (*r == '\0') {
	    *arg++ = r + 1;
	}
    }

fail_args:
    return argc;
fail_args_ptr:
    free(args);
    return 0;
}

/* Free argv created by parse_args1()
 *	argv	Argument Values
 */
void free_args1(char ***argv)
{
    char *s;
    s = **argv;
    free(*argv);
    free(s);
}

/* Convert a string to an argc/argv pair
 *	str	String to parse
 *	argv	Argument Values
 *	returns	Argument Count
 */
int rosh_str2argv(char ***argv, const char *str)
{
    return parse_args1(argv, str);
}

/* Free an argv created by rosh_str2argv()
 *	argv	Argument Values to free
 */
void rosh_free_argv(char ***argv)
{
     free_args1(argv);
}

/* Print the contents of an argc/argv pair
 *	argc	Argument Count
 *	argv	Argument Values
 */
void rosh_pr_argv(int argc, char *argv[])
{
    int i;
    for (i = 0; i < argc; i++) {
	printf("%s%s", argv[i], (i < argc)? " " : "");
    }
    puts("");
}

/* Print the contents of an argc/argv pair verbosely
 *	argc	Argument Count
 *	argv	Argument Values
 */
void rosh_pr_argv_v(int argc, char *argv[])
{
    int i;
    for (i = 0; i < argc; i++) {
	printf("%4d '%s'\n", i, argv[i]);
    }
}

/* Reset the getopt() environment
 */
void rosh_getopt_reset(void)
{
    optind = 0;
    optopt = 0;
}

/* Display help
 *	type	Help type
 *	cmdstr	Command for which help is requested
 */
void rosh_help(int type, const char *cmdstr)
{
    switch (type) {
    case 2:
	if ((cmdstr == NULL) || (strcmp(cmdstr, "") == 0)) {
	    rosh_version(0);
	    puts(rosh_help_str2);
	} else {
	    switch (cmdstr[0]) {
	    case 'c':
		puts(rosh_help_cd_str);
		break;
	    case 'l':
		puts(rosh_help_ls_str);
		break;
	    default:
		printf(rosh_help_str_adv, cmdstr);
	    }
	}
	break;
    case 1:
    default:
	if (cmdstr)
	    printf("%s: %s: unknown command\n", APP_NAME, cmdstr);
	rosh_version(0);
	puts(rosh_help_str1);
    }
}

/* Handle most/all errors
 *	ierrno	Input Error number
 *	cmdstr	Command being executed to cause error
 *	filestr	File/parameter causing error
 */
void rosh_error(const int ierrno, const char *cmdstr, const char *filestr)
{
    printf("--ERROR: %s '%s': ", cmdstr, filestr);
    switch (ierrno) {
    case 0:
	puts("NO ERROR");
	break;
    case ENOENT:
	puts("not found");
	/* SYSLinux-3.72 COM32 API returns this for a
	   directory or empty file */
	ROSH_COM32("  (COM32) could be a directory or empty file\n");
	break;
    case EIO:
	puts("I/O Error");
	break;
    case EBADF:
	puts("Bad File Descriptor");
	break;
    case EACCES:
	puts("Access DENIED");
	break;
    case ENOTDIR:
	puts("not a directory");
	ROSH_COM32("  (COM32) could be directory\n");
	break;
    case EISDIR:
	puts("IS a directory");
	break;
    case ENOSYS:
	puts("not implemented");
	break;
    default:
	printf("returns error; errno=%d\n", ierrno);
    }
}				/* rosh_error */

/* Concatenate command line arguments into one string
 *	cmdstr	Output command string
 *	cmdlen	Length of cmdstr
 *	argc	Argument Count
 *	argv	Argument Values
 *	barg	Beginning Argument
 */
int rosh_argcat(char *cmdstr, const int cmdlen, const int argc, char *argv[],
		const int barg)
{
    int i, arglen, curpos;	/* index, argument length, current position
				   in cmdstr */
    curpos = 0;
    cmdstr[0] = '\0';		/* Nullify string just to be sure */
    for (i = barg; i < argc; i++) {
	arglen = strlen(argv[i]);
	/* Theoretically, this should never be met in SYSLINUX */
	if ((curpos + arglen) > (cmdlen - 1))
	    arglen = (cmdlen - 1) - curpos;
	memcpy(cmdstr + curpos, argv[i], arglen);
	curpos += arglen;
	if (curpos >= (cmdlen - 1)) {
	    /* Hopefully, curpos should not be greater than
	       (cmdlen - 1) */
	    /* Still need a '\0' at the last character */
	    cmdstr[(cmdlen - 1)] = 0;
	    break;		/* Escape out of the for() loop;
				   We can no longer process anything more */
	} else {
	    cmdstr[curpos] = ' ';
	    curpos += 1;
	    cmdstr[curpos] = 0;
	}
    }
    /* If there's a ' ' at the end, remove it.  This is normal unless
       the maximum length is met/exceeded. */
    if (cmdstr[curpos - 1] == ' ')
	cmdstr[--curpos] = 0;
    return curpos;
}				/* rosh_argcat */

/*
 * Prints a lot of the data in a struct termios
 */
/*
void rosh_print_tc(struct termios *tio)
{
	printf("  -- termios: ");
	printf(".c_iflag=%04X ", tio->c_iflag);
	printf(".c_oflag=%04X ", tio->c_oflag);
	printf(".c_cflag=%04X ", tio->c_cflag);
	printf(".c_lflag=%04X ", tio->c_lflag);
	printf(".c_cc[VTIME]='%d' ", tio->c_cc[VTIME]);
	printf(".c_cc[VMIN]='%d'", tio->c_cc[VMIN]);
	printf("\n");
}
*/

/*
 * Attempts to get a single key from the console
 *	returns	key pressed
 */
int rosh_getkey(void)
{
    int inc;

    inc = KEY_NONE;
    while (inc == KEY_NONE)
	inc = get_key(stdin, 6000);
    return inc;
}				/* rosh_getkey */

/*
 * Qualifies a filename relative to the working directory
 *	filestr	Filename to qualify
 *	pwdstr	working directory
 *	returns	qualified file name string
 */
void rosh_qualify_filestr(char *filestr, const char *ifilstr,
			  const char *pwdstr)
{
    int filepos = 0;
    if ((filestr) && (pwdstr) && (ifilstr)) {
	if (ifilstr[0] != SEP) {
	    strcpy(filestr, pwdstr);
	    filepos = strlen(pwdstr);
	    if (filestr[filepos - 1] != SEP)
		filestr[filepos++] = SEP;
	}
	strcpy(filestr + filepos, ifilstr);
	ROSH_DEBUG("--'%s'\n", filestr);
    }
}

/* Concatenate multiple files to stdout
 *	argc	Argument Count
 *	argv	Argument Values
 */
void rosh_cat(int argc, char *argv[])
{
    FILE *f;
    char buf[ROSH_BUF_SZ];
    int i, numrd;

    for (i = 0; i < argc; i++) {
	printf("--File = '%s'\n", argv[i]);
	errno = 0;
	f = fopen(argv[i], "r");
	if (f != NULL) {
	    numrd = fread(buf, 1, ROSH_BUF_SZ, f);
	    while (numrd > 0) {
		fwrite(buf, 1, numrd, stdout);
		numrd = fread(buf, 1, ROSH_BUF_SZ, f);
	    }
	    fclose(f);
	} else {
	    rosh_error(errno, "cat", argv[i]);
	    errno = 0;
	}
    }
}				/* rosh_cat */

/* Change PWD (Present Working Directory)
 *	argc	Argument count
 *	argv	Argument values
 *	ipwdstr	Initial PWD
 */
void rosh_cd(int argc, char *argv[], const char *ipwdstr)
{
    int rv = 0;
#ifdef DO_DEBUG
    char filestr[ROSH_PATH_SZ];
#endif /* DO_DEBUG */
    ROSH_DEBUG("CMD: \n");
    ROSH_DEBUG_ARGV_V(argc, argv);
    errno = 0;
    if (argc == 2)
	rv = chdir(argv[1]);
    else if (argc == 1)
	rv = chdir(ipwdstr);
    else
	rosh_help(2, argv[0]);
    if (rv != 0) {
	if (argc == 2)
	    rosh_error(errno, "cd", argv[1]);
	else
	    rosh_error(errno, "cd", ipwdstr);
	errno = 0;
    } else {
#ifdef DO_DEBUG
	if (getcwd(filestr, ROSH_PATH_SZ))
	    ROSH_DEBUG("  %s\n", filestr);
#endif /* DO_DEBUG */
    }
}				/* rosh_cd */

/* Print the syslinux config file name
 */
void rosh_cfg(void)
{
    printf("CFG:     '%s'\n", syslinux_config_file());
}				/* rosh_cfg */

/* Echo a string back to the screen
 *	cmdstr	command string to process
 */
void rosh_echo(const char *cmdstr)
{
    int bpos = 0;
    ROSH_DEBUG("CMD: '%s'\n", cmdstr);
    bpos = rosh_search_nonsp(cmdstr, rosh_search_sp(cmdstr, 0));
    if (bpos > 1) {
	ROSH_DEBUG("  bpos=%d\n", bpos);
	printf("'%s'\n", cmdstr + bpos);
    } else {
	puts("");
    }
}				/* rosh_echo */

/* Process argc/argv to optarr
 *	argc	Argument count
 *	argv	Argument values
 *	optarr	option array to populate
 */
void rosh_ls_arg_opt(int argc, char *argv[], int optarr[])
{
    int rv = 0;

    optarr[0] = -1;
    optarr[1] = -1;
    optarr[2] = -1;
    rosh_getopt_reset();
    while (rv != -1) {
	ROSH_DEBUG2("getopt optind=%d rv=%d\n", optind, rv);
	rv = getopt(argc, argv, rosh_ls_opt_str);
	switch (rv) {
	case 'l':
	case 0:
	    optarr[0] = 1;
	    break;
	case 'F':
	case 1:
	    optarr[1] = 1;
	    break;
	case 'i':
	case 2:
	    optarr[2] = 1;
	    break;
	case '?':
	case -1:
	default:
	    ROSH_DEBUG2("getopt optind=%d rv=%d\n", optind, rv);
	    break;
	}
    }
    ROSH_DEBUG2(" end getopt optind=%d rv=%d\n", optind, rv);
    ROSH_DEBUG2("\tIn rosh_ls_arg_opt() opt[0]=%d\topt[1]=%d\topt[2]=%d\n", optarr[0], optarr[1],
	       optarr[2]);
}				/* rosh_ls_arg_opt */

/* Retrieve the size of a file argument
 *	filestr	directory name of directory entry
 *	de	directory entry
 */
int rosh_ls_de_size(const char *filestr, struct dirent *de)
{
    int de_size;
    char filestr2[ROSH_PATH_SZ];
    int fd2, file2pos;
    struct stat fdstat;

    filestr2[0] = 0;
    file2pos = -1;
    if (filestr) {
	file2pos = strlen(filestr);
	memcpy(filestr2, filestr, file2pos);
	filestr2[file2pos] = '/';
    }
    strcpy(filestr2 + file2pos + 1, de->d_name);
    fd2 = open(filestr2, O_RDONLY);
    fstat(fd2, &fdstat);
    fd2 = close(fd2);
    de_size = (int)fdstat.st_size;
    return de_size;
}				/* rosh_ls_de_size */

/* Retrieve the size and mode of a file
 *	filestr	directory name of directory entry
 *	de	directory entry
 */
int rosh_ls_de_size_mode(const char *filestr, struct dirent *de, mode_t * st_mode)
{
    int de_size;
    char filestr2[ROSH_PATH_SZ];
    int file2pos;
    struct stat fdstat;
    int status;

    filestr2[0] = 0;
    file2pos = -1;
    memset(&fdstat, 0, sizeof fdstat);
    ROSH_DEBUG2("ls:dsm(%s, %s) ", filestr, de->d_name);
    if (filestr) {
	/* FIXME: prevent string overflow */
	file2pos = strlen(filestr);
	memcpy(filestr2, filestr, file2pos);
	if (( filestr2[file2pos - 1] == SEP )) {
	    file2pos--;
	} else {
	    filestr2[file2pos] = SEP;
	}
    }
    strcpy(filestr2 + file2pos + 1, de->d_name);
    errno = 0;
    ROSH_DEBUG2("stat(%s) ", filestr2);
    status = stat(filestr2, &fdstat);
    (void)status;
    ROSH_DEBUG2("\t--stat()=%d\terr=%d\n", status, errno);
    if (errno) {
	rosh_error(errno, "ls:szmd.stat", de->d_name);
	errno = 0;
    }
    de_size = (int)fdstat.st_size;
    *st_mode = fdstat.st_mode;
    return de_size;
}				/* rosh_ls_de_size_mode */

/* Returns the Inode number if fdstat contains it
 *	fdstat	struct to extract inode from if not COM32, for now
 */
long rosh_ls_d_ino(struct stat *fdstat)
{
    long de_ino;
#ifdef __COM32__
    if (fdstat)
	de_ino = -1;
    else
	de_ino = 0;
#else /* __COM32__ */
    de_ino = fdstat->st_ino;
#endif /* __COM32__ */
    return de_ino;
}

/* Convert a d_type to a single char in human readable format
 *	d_type	d_type to convert
 *	returns human readable single character; a space if other
 */
char rosh_d_type2char_human(unsigned char d_type)
{
    char ret;
    switch (d_type) {
    case DT_UNKNOWN:
	ret = 'U';
	break;			/* Unknown */
    case DT_FIFO:
	ret = 'F';
	break;			/* FIFO */
    case DT_CHR:
	ret = 'C';
	break;			/* Char Dev */
    case DT_DIR:
	ret = 'D';
	break;			/* Directory */
    case DT_BLK:
	ret = 'B';
	break;			/* Block Dev */
    case DT_REG:
	ret = 'R';
	break;			/* Regular File */
    case DT_LNK:
	ret = 'L';
	break;			/* Link, Symbolic */
    case DT_SOCK:
	ret = 'S';
	break;			/* Socket */
    case DT_WHT:
	ret = 'W';
	break;			/* UnionFS Whiteout */
    default:
	ret = ' ';
    }
    return ret;
}				/* rosh_d_type2char_human */

/* Convert a d_type to a single char by ls's prefix standards for -l
 *	d_type	d_type to convert
 *	returns ls style single character; a space if other
 */
char rosh_d_type2char_lspre(unsigned char d_type)
{
    char ret;
    switch (d_type) {
    case DT_FIFO:
	ret = 'p';
	break;
    case DT_CHR:
	ret = 'c';
	break;
    case DT_DIR:
	ret = 'd';
	break;
    case DT_BLK:
	ret = 'b';
	break;
    case DT_REG:
	ret = '-';
	break;
    case DT_LNK:
	ret = 'l';
	break;
    case DT_SOCK:
	ret = 's';
	break;
    default:
	ret = '?';
    }
    return ret;
}				/* rosh_d_type2char_lspre */

/* Convert a d_type to a single char by ls's classify (-F) suffix standards
 *	d_type	d_type to convert
 *	returns ls style single character; a space if other
 */
char rosh_d_type2char_lssuf(unsigned char d_type)
{
    char ret;
    switch (d_type) {
    case DT_FIFO:
	ret = '|';
	break;
    case DT_DIR:
	ret = '/';
	break;
    case DT_LNK:
	ret = '@';
	break;
    case DT_SOCK:
	ret = '=';
	break;
    default:
	ret = ' ';
    }
    return ret;
}				/* rosh_d_type2char_lssuf */

/* Converts data in the "other" place of st_mode to a ls-style string
 *	st_mode	Mode in other to analyze
 *	st_mode_str	string to hold converted string
 */
void rosh_st_mode_am2str(mode_t st_mode, char *st_mode_str)
{
    st_mode_str[0] = ((st_mode & S_IROTH) ? 'r' : '-');
    st_mode_str[1] = ((st_mode & S_IWOTH) ? 'w' : '-');
    st_mode_str[2] = ((st_mode & S_IXOTH) ? 'x' : '-');
}

/* Converts st_mode to an ls-style string
 *	st_mode	mode to convert
 *	st_mode_str	string to hold converted string
 */
void rosh_st_mode2str(mode_t st_mode, char *st_mode_str)
{
    st_mode_str[0] = rosh_d_type2char_lspre(IFTODT(st_mode));
    rosh_st_mode_am2str((st_mode & S_IRWXU) >> 6, st_mode_str + 1);
    rosh_st_mode_am2str((st_mode & S_IRWXG) >> 3, st_mode_str + 4);
    rosh_st_mode_am2str(st_mode & S_IRWXO, st_mode_str + 7);
    st_mode_str[10] = 0;
}				/* rosh_st_mode2str */

/* Output a single entry
 *	filestr	directory name to list
 *	de	directory entry
 *	optarr	Array of options
 */
void rosh_ls_arg_dir_de(const char *filestr, struct dirent *de, const int *optarr)
{
    int de_size;
    mode_t st_mode;
    char st_mode_str[11];
    st_mode = 0;
    ROSH_DEBUG2("+");
    if (optarr[2] > -1)
	printf("%10d ", (int)(de->d_ino));
    if (optarr[0] > -1) {
	de_size = rosh_ls_de_size_mode(filestr, de, &st_mode);
	rosh_st_mode2str(st_mode, st_mode_str);
	ROSH_DEBUG2("%04X ", st_mode);
	printf("%s %10d ", st_mode_str, de_size);
    }
    ROSH_DEBUG("'");
    printf("%s", de->d_name);
    ROSH_DEBUG("'");
    if (optarr[1] > -1)
	printf("%c", rosh_d_type2char_lssuf(de->d_type));
    printf("\n");
}				/* rosh_ls_arg_dir_de */

/* Output listing of a regular directory
 *	filestr	directory name to list
 *	d	the open DIR
 *	optarr	Array of options
	NOTE:This is where I could use qsort
 */
void rosh_ls_arg_dir(const char *filestr, DIR * d, const int *optarr)
{
    struct dirent *de;
    int filepos;

    filepos = 0;
    errno = 0;
    while ((de = readdir(d))) {
	filepos++;
	rosh_ls_arg_dir_de(filestr, de, optarr);
    }
    if (errno) {
	rosh_error(errno, "ls:arg_dir", filestr);
	errno = 0;
    } else { if (filepos == 0)
	ROSH_DEBUG("0 files found");
    }
}				/* rosh_ls_arg_dir */

/* Simple directory listing for one argument (file/directory) based on
 * filestr and pwdstr
 *	ifilstr	input filename/directory name to list
 *	pwdstr	Present Working Directory string
 *	optarr	Option Array
 */
void rosh_ls_arg(const char *filestr, const int *optarr)
{
    struct stat fdstat;
    int status;
//     char filestr[ROSH_PATH_SZ];
//     int filepos;
    DIR *d;
    struct dirent de;

    /* Initialization; make filestr based on leading character of ifilstr
       and pwdstr */
//     rosh_qualify_filestr(filestr, ifilstr, pwdstr);
    fdstat.st_mode = 0;
    fdstat.st_size = 0;
    ROSH_DEBUG("\topt[0]=%d\topt[1]=%d\topt[2]=%d\n", optarr[0], optarr[1],
	       optarr[2]);

    /* Now, the real work */
    errno = 0;
    status = stat(filestr, &fdstat);
    if (status == 0) {
	if (S_ISDIR(fdstat.st_mode)) {
	    ROSH_DEBUG("PATH '%s' is a directory\n", filestr);
	    if ((d = opendir(filestr))) {
		rosh_ls_arg_dir(filestr, d, optarr);
		closedir(d);
	    } else {
		rosh_error(errno, "ls", filestr);
		errno = 0;
	    }
	} else {
	    de.d_ino = rosh_ls_d_ino(&fdstat);
	    de.d_type = (IFTODT(fdstat.st_mode));
	    strcpy(de.d_name, filestr);
	    if (S_ISREG(fdstat.st_mode)) {
		ROSH_DEBUG("PATH '%s' is a regular file\n", filestr);
	    } else {
		ROSH_DEBUG("PATH '%s' is some other file\n", filestr);
	    }
	    rosh_ls_arg_dir_de(NULL, &de, optarr);
/*	    if (ifilstr[0] == SEP)
		rosh_ls_arg_dir_de(NULL, &de, optarr);
	    else
		rosh_ls_arg_dir_de(pwdstr, &de, optarr);*/
	}
    } else {
	rosh_error(errno, "ls", filestr);
	errno = 0;
    }
    return;
}				/* rosh_ls_arg */

/* Parse options that may be present in the cmdstr
 *	filestr	Possible option string to parse
 *	optstr	Current options
 *	returns 1 if filestr does not begin with '-' else 0
 */
int rosh_ls_parse_opt(const char *filestr, char *optstr)
{
    int ret;
    if (filestr[0] == '-') {
	ret = 0;
	if (optstr)
	    strcat(optstr, filestr + 1);
    } else {
	ret = 1;
    }
    ROSH_DEBUG("ParseOpt: '%s'\n\topt: '%s'\n\tret: %d\n", filestr, optstr,
	       ret);
    return ret;
}				/* rosh_ls_parse_opt */

/* List Directory
 *	argc	Argument count
 *	argv	Argument values
 */
void rosh_ls(int argc, char *argv[])
{
    int optarr[3];
    int i;

    rosh_ls_arg_opt(argc, argv, optarr);
    ROSH_DEBUG2("In ls()\n");
    ROSH_DEBUG2_ARGV_V(argc, argv);
#ifdef DO_DEBUG
    optarr[0] = 2;
#endif /* DO_DEBUG */
    ROSH_DEBUG2("  argc=%d; optind=%d\n", argc, optind);
    if (optind >= argc)
	rosh_ls_arg(".", optarr);
    for (i = optind; i < argc; i++) {
	rosh_ls_arg(argv[i], optarr);
    }
}				/* rosh_ls */

/* Simple directory listing; calls rosh_ls()
 *	argc	Argument count
 *	argv	Argument values
 */
void rosh_dir(int argc, char *argv[])
{
    ROSH_DEBUG("  dir implemented as ls\n");
    rosh_ls(argc, argv);
}				/* rosh_dir */

/* Page through a buffer string
 *	buf	Buffer to page through
 */
void rosh_more_buf(char *buf, int buflen, int rows, int cols, char *scrbuf)
{
    char *bufp, *bufeol, *bufeol2;	/* Pointer to current and next
					   end-of-line position in buffer */
    int bufpos, bufcnt;		/* current position, count characters */
    int inc;
    int i, numln;		/* Index, Number of lines */
    int elpl;		/* Extra lines per line read */

    (void)cols;

    bufpos = 0;
    bufp = buf + bufpos;
    bufeol = bufp;
    numln = rows - 1;
    ROSH_DEBUG("--(%d)\n", buflen);
    while (bufpos < buflen) {
	for (i = 0; i < numln; i++) {
	    bufeol2 = strchr(bufeol, '\n');
	    if (bufeol2 == NULL) {
		bufeol = buf + buflen;
		i = numln;
	    } else {
		elpl = ((bufeol2 - bufeol - 1) / cols);
		if (elpl < 0)
		    elpl = 0;
		i += elpl;
		ROSH_DEBUG2("  %d/%d  ", elpl, i+1);
		/* If this will not push too much, use it */
		/* but if it's the first line, use it */
		/* //HERE: We should probably snip the line off */
		if ((i < numln) || (i == elpl))
		    bufeol = bufeol2 + 1;
	    }
	}
	ROSH_DEBUG2("\n");
	bufcnt = bufeol - bufp;
	printf("--(%d/%d @%d)\n", bufcnt, buflen, bufpos);
	memcpy(scrbuf, bufp, bufcnt);
	scrbuf[bufcnt] = 0;
	printf("%s", scrbuf);
	bufp = bufeol;
	bufpos += bufcnt;
	if (bufpos == buflen)
	    break;
	inc = rosh_getkey();
	numln = 1;
	switch (inc) {
	case KEY_CTRL('c'):
	case 'q':
	case 'Q':
	    bufpos = buflen;
	    break;
	case ' ':
	    numln = rows - 1;
	}
    }
}				/* rosh_more_buf */

/* Page through a single file using the open file stream
 *	fd	File Descriptor
 */
void rosh_more_fd(int fd, int rows, int cols, char *scrbuf)
{
    struct stat fdstat;
    char *buf;
    int bufpos;
    int numrd;
    FILE *f;

    fstat(fd, &fdstat);
    if (S_ISREG(fdstat.st_mode)) {
	buf = malloc((int)fdstat.st_size);
	if (buf != NULL) {
	    f = fdopen(fd, "r");
	    bufpos = 0;
	    numrd = fread(buf, 1, (int)fdstat.st_size, f);
	    while (numrd > 0) {
		bufpos += numrd;
		numrd = fread(buf + bufpos, 1,
			      ((int)fdstat.st_size - bufpos), f);
	    }
	    fclose(f);
	    rosh_more_buf(buf, bufpos, rows, cols, scrbuf);
	}
    } else {
    }

}				/* rosh_more_fd */

/* Page through a file like the more command
 *	argc	Argument Count
 *	argv	Argument Values
 */
void rosh_more(int argc, char *argv[])
{
    int fd, i;
/*    char filestr[ROSH_PATH_SZ];
    int cmdpos;*/
    int rows, cols;
    char *scrbuf;
    int ret;

    ROSH_DEBUG_ARGV_V(argc, argv);
    ret = getscreensize(1, &rows, &cols);
    if (ret) {
	ROSH_DEBUG("getscreensize() fail(%d); fall back\n", ret);
	ROSH_DEBUG("\tROWS='%d'\tCOLS='%d'\n", rows, cols);
	/* If either fail, go under normal size, just in case */
	if (!rows)
	    rows = 20;
	if (!cols)
	    cols = 75;
    }
    ROSH_DEBUG("\tUSE ROWS='%d'\tCOLS='%d'\n", rows, cols);
    /* 32 bit align beginning of row and over allocate */
    scrbuf = malloc(rows * ((cols+3)&(INT_MAX - 3)));
    if (!scrbuf)
	return;

    if (argc) {
	/* There is no need to mess up the console if we don't have a
	   file */
	rosh_console_raw();
	for (i = 0; i < argc; i++) {
	    printf("--File = '%s'\n", argv[i]);
	    errno = 0;
	    fd = open(argv[i], O_RDONLY);
	    if (fd != -1) {
		rosh_more_fd(fd, rows, cols, scrbuf);
		close(fd);
	    } else {
		rosh_error(errno, "more", argv[i]);
		errno = 0;
	    }
	}
	rosh_console_std();
    }
    free(scrbuf);
}				/* rosh_more */

/* Page a file with rewind
 *	argc	Argument Count
 *	argv	Argument Values
 */
void rosh_less(int argc, char *argv[])
{
    printf("  less implemented as more (for now)\n");
    rosh_more(argc, argv);
}				/* rosh_less */

/* Show PWD
 */
void rosh_pwd(void)
{
    char pwdstr[ROSH_PATH_SZ];
    errno = 0;
    if (getcwd(pwdstr, ROSH_PATH_SZ)) {
	printf("%s\n", pwdstr);
    } else {
	rosh_error(errno, "pwd", "");
	errno = 0;
    }
}				/* rosh_pwd */

/* Reboot; use warm reboot if one of certain options set
 *	argc	Argument count
 *	argv	Argument values
 */
void rosh_reboot(int argc, char *argv[])
{
    int rtype = 0;
    if (argc) {
	/* For now, just use the first */
	switch (argv[0][0]) {
	case '1':
	case 's':
	case 'w':
	    rtype = 1;
	    break;
	case '-':
	    switch (argv[0][1]) {
	    case '1':
	    case 's':
	    case 'w':
		rtype = 1;
		break;
	    }
	    break;
	}
    }
    syslinux_reboot(rtype);
}				/* rosh_reboot */

/* Run a boot string, calling syslinux_run_command
 *	argc	Argument count
 *	argv	Argument values
 */
void rosh_run(int argc, char *argv[])
{
    char cmdstr[ROSH_CMD_SZ];
    int len;

    len = rosh_argcat(cmdstr, ROSH_CMD_SZ, argc, argv, 0);
    if (len) {
	printf("--run: '%s'\n", cmdstr);
	syslinux_run_command(cmdstr);
    } else {
	printf(APP_NAME ":run: No arguments\n");
    }
}				/* rosh_run */

/* Process an argc/argv pair and call handling function
 *	argc	Argument count
 *	argv	Argument values
 *	ipwdstr	Initial Present Working Directory string
 *	returns	Whether to exit prompt
 */
char rosh_command(int argc, char *argv[], const char *ipwdstr)
{
    char do_exit = false;
    int tlen;
    tlen = strlen(argv[0]);
    ROSH_DEBUG_ARGV_V(argc, argv);
    switch (argv[0][0]) {
    case 'e':
    case 'E':
    case 'q':
    case 'Q':
	switch (argv[0][1]) {
	case 0:
	case 'x':
	case 'X':
	case 'u':
	case 'U':
	    if ((strncasecmp("exit", argv[0], tlen) == 0) ||
		(strncasecmp("quit", argv[0], tlen) == 0))
		do_exit = true;
	    else
		rosh_help(1, argv[0]);
	    break;
	case 'c':
	case 'C':
	    if (strncasecmp("echo", argv[0], tlen) == 0)
		rosh_pr_argv(argc - 1, &argv[1]);
	    else
		rosh_help(1, argv[0]);
	    break;
	default:
	    rosh_help(1, argv[0]);
	}
	break;
    case 'c':
    case 'C':			/* run 'cd' 'cat' 'cfg' */
	switch (argv[0][1]) {
	case 'a':
	case 'A':
	    if (strncasecmp("cat", argv[0], tlen) == 0)
		rosh_cat(argc - 1, &argv[1]);
	    else
		rosh_help(1, argv[0]);
	    break;
	case 'd':
	case 'D':
	    if (strncasecmp("cd", argv[0], tlen) == 0)
		rosh_cd(argc, argv, ipwdstr);
	    else
		rosh_help(1, argv[0]);
	    break;
	case 'f':
	case 'F':
	    if (strncasecmp("cfg", argv[0], tlen) == 0)
		rosh_cfg();
	    else
		rosh_help(1, argv[0]);
	    break;
	default:
	    rosh_help(1, argv[0]);
	}
	break;
    case 'd':
    case 'D':			/* run 'dir' */
	if (strncasecmp("dir", argv[0], tlen) == 0)
	    rosh_dir(argc - 1, &argv[1]);
	else
	    rosh_help(1, argv[0]);
	break;
    case 'h':
    case 'H':
    case '?':
	if ((strncasecmp("help", argv[0], tlen) == 0) || (tlen == 1))
	    rosh_help(2, argv[1]);
	else
	    rosh_help(1, NULL);
	break;
    case 'l':
    case 'L':			/* run 'ls' 'less' */
	switch (argv[0][1]) {
	case 0:
	case 's':
	case 'S':
	    if (strncasecmp("ls", argv[0], tlen) == 0)
		rosh_ls(argc, argv);
	    else
		rosh_help(1, argv[0]);
	    break;
	case 'e':
	case 'E':
	    if (strncasecmp("less", argv[0], tlen) == 0)
		rosh_less(argc - 1, &argv[1]);
	    else
		rosh_help(1, argv[0]);
	    break;
	default:
	    rosh_help(1, argv[0]);
	}
	break;
    case 'm':
    case 'M':
	switch (argv[0][1]) {
	case 'a':
	case 'A':
	    if (strncasecmp("man", argv[0], tlen) == 0)
		rosh_help(2, argv[1]);
	    else
		rosh_help(1, argv[0]);
	    break;
	case 'o':
	case 'O':
	    if (strncasecmp("more", argv[0], tlen) == 0)
		rosh_more(argc - 1, &argv[1]);
	    else
		rosh_help(1, argv[0]);
	    break;
	default:
	    rosh_help(1, argv[0]);
	}
	break;
    case 'p':
    case 'P':			/* run 'pwd' */
	if (strncasecmp("pwd", argv[0], tlen) == 0)
	    rosh_pwd();
	else
	    rosh_help(1, argv[0]);
	break;
    case 'r':
    case 'R':			/* run 'run' */
	switch (argv[0][1]) {
	case 0:
	case 'e':
	case 'E':
	    if (strncasecmp("reboot", argv[0], tlen) == 0)
		rosh_reboot(argc - 1, &argv[1]);
	    else
		rosh_help(1, argv[0]);
	    break;
	case 'u':
	case 'U':
	    if (strncasecmp("run", argv[0], tlen) == 0)
		rosh_run(argc - 1, &argv[1]);
	    else
		rosh_help(1, argv[0]);
	    break;
	default:
	    rosh_help(1, argv[0]);
	}
	break;
    case 'v':
    case 'V':
	if (strncasecmp("version", argv[0], tlen) == 0)
	    rosh_version(1);
	else
	    rosh_help(1, argv[0]);
	break;
    case 0:
    case '\n':
	break;
    default:
	rosh_help(1, argv[0]);
    }				/* switch(argv[0][0]) */
    return do_exit;
}				/* rosh_command */

/* Process the prompt for commands as read from stdin and call rosh_command
 * to process command line string
 *	icmdstr	Initial command line string
 *	returns	Exit status
 */
int rosh_prompt(int iargc, char *iargv[])
{
    int rv;
    char cmdstr[ROSH_CMD_SZ];
    char ipwdstr[ROSH_PATH_SZ];
    char do_exit;
    char **argv;
    int argc;

    rv = 0;
    do_exit = false;
    if (!getcwd(ipwdstr, ROSH_PATH_SZ))
	strcpy(ipwdstr, "./");
    if (iargc > 1)
	do_exit = rosh_command(iargc - 1, &iargv[1], ipwdstr);
    while (!(do_exit)) {
	/* Extra preceeding newline */
	printf("\nrosh: ");
	/* Read a line from console */
	if (fgets(cmdstr, ROSH_CMD_SZ, stdin)) {
	    argc = rosh_str2argv(&argv, cmdstr);
	    do_exit = rosh_command(argc, argv, ipwdstr);
	    rosh_free_argv(&argv);
	} else {
	    do_exit = false;
	}
    }
    return rv;
}

int main(int argc, char *argv[])
{
    int rv;

    /* Initialization */
    rv = 0;
    rosh_console_std();
    if (argc == 1) {
	rosh_version(0);
	print_beta();
    } else {
#ifdef DO_DEBUG
	char cmdstr[ROSH_CMD_SZ];
	rosh_argcat(cmdstr, ROSH_CMD_SZ, argc, argv, 1);
	ROSH_DEBUG("arg='%s'\n", cmdstr);
#endif
    }
    rv = rosh_prompt(argc, argv);
    printf("--Exiting '" APP_NAME "'\n");
    return rv;
}
