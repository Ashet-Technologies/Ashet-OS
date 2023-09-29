/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2007-2008 H. Peter Anvin - All Rights Reserved
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

#include <getkey.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <syslinux/boot.h>

#define lnetlib_c		/* Define the library */

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "syslinux/boot.h"
#include "syslinux/loadfile.h"
#include "syslinux/linux.h"
#include "syslinux/config.h"
#include "syslinux/reboot.h"

int __parse_argv(char ***argv, const char *str);

#define SYSLINUX_FILE "syslinux_file"

typedef struct syslinux_file {
    char *data;
    char *name;
    size_t size;
} syslinux_file;

/*
 * Most code taken from:
 *	com32/modules/linux.c
 */

/* Find the last instance of a particular command line argument
   (which should include the final =; do not use for boolean arguments) */
static char *find_argument(char **argv, const char *argument)
{
    int la = strlen(argument);
    char **arg;
    char *ptr = NULL;

    for (arg = argv; *arg; arg++) {
	if (!memcmp(*arg, argument, la))
	    ptr = *arg + la;
    }

    return ptr;
}

/* Get a value with a potential suffix (k/m/g/t/p/e) */
static unsigned long long suffix_number(const char *str)
{
    char *ep;
    unsigned long long v;
    int shift;

    v = strtoull(str, &ep, 0);
    switch (*ep | 0x20) {
    case 'k':
	shift = 10;
	break;
    case 'm':
	shift = 20;
	break;
    case 'g':
	shift = 30;
	break;
    case 't':
	shift = 40;
	break;
    case 'p':
	shift = 50;
	break;
    case 'e':
	shift = 60;
	break;
    default:
	shift = 0;
	break;
    }
    v <<= shift;

    return v;
}

/* Truncate to 32 bits, with saturate */
static inline uint32_t saturate32(unsigned long long v)
{
    return (v > 0xffffffff) ? 0xffffffff : (uint32_t) v;
}

/* Stitch together the command line from a set of argv's */
static char *make_cmdline(char **argv)
{
    char **arg;
    size_t bytes;
    char *cmdline, *p;

    bytes = 1;			/* Just in case we have a zero-entry cmdline */
    for (arg = argv; *arg; arg++) {
	bytes += strlen(*arg) + 1;
    }

    p = cmdline = malloc(bytes);
    if (!cmdline)
	return NULL;

    for (arg = argv; *arg; arg++) {
	int len = strlen(*arg);
	memcpy(p, *arg, len);
	p[len] = ' ';
	p += len + 1;
    }

    if (p > cmdline)
	p--;			/* Remove the last space */
    *p = '\0';

    return cmdline;
}

static int sl_run_command(lua_State * L)
{
    const char *cmd = luaL_checkstring(L, 1);	/* Reads the string parameter */
    syslinux_run_command(cmd);
    return 0;
}

/* do default boot */
static int sl_run_default(lua_State * L)
{
    /* Preventing GCC to complain against unused L */
    L=L;
    syslinux_run_default();
    return 0;
}

/* do local boot */
static int sl_local_boot(lua_State * L)
{
    uint16_t flags = luaL_checkint(L, 1);
    syslinux_local_boot(flags);
    return 0;
}

static int sl_final_cleanup(lua_State * L)
{
    uint16_t flags = luaL_checkint(L, 1);
    syslinux_local_boot(flags);
    return 0;
}

/* boot linux kernel and initrd */
static int sl_boot_linux(lua_State * L)
{
    const char *kernel = luaL_checkstring(L, 1);
    const char *cmdline = luaL_optstring(L, 2, "");
    char *initrd;
    void *kernel_data, *file_data;
    size_t kernel_len, file_len;
    struct initramfs *initramfs;
    char *newcmdline;
    uint32_t mem_limit = luaL_optint(L, 3, 0);
    uint16_t video_mode = luaL_optint(L, 4, 0);
    int ret;
    char **argv, **argp, *arg, *p;

    (void)mem_limit;
    (void)video_mode;

    ret = __parse_argv(&argv, cmdline);

    newcmdline = malloc(strlen(kernel) + 12);
    if (!newcmdline)
	printf("Mem alloc failed: cmdline\n");

    strcpy(newcmdline, "BOOT_IMAGE=");
    strcpy(newcmdline + strlen(newcmdline), kernel);
    argv[0] = newcmdline;
    argp = argv;

    /* DEBUG
       for (i=0; i<ret; i++)
       printf("%d: %s\n", i, argv[i]);
     */

    newcmdline = make_cmdline(argp);
    if (!newcmdline)
	printf("Creating command line failed!\n");

    /* DEBUG
       printf("Command line: %s\n", newcmdline);
       msleep(1000);
     */

    printf("Loading kernel %s...\n", kernel);
    if (loadfile(kernel, &kernel_data, &kernel_len))
	printf("failed!\n");
    else
	printf("ok\n");

    initramfs = initramfs_init();
    if (!initramfs)
	printf("Initializing initrd failed!\n");

    if ((arg = find_argument(argp, "initrd="))) {
	do {
	    p = strchr(arg, ',');
	    if (p)
		*p = '\0';

	    initrd = arg;
	    printf("Loading initrd %s... ", initrd);
	    if (initramfs_load_archive(initramfs, initrd)) {
		printf("failed!\n");
	    }
	    printf("ok\n");

	    if (p)
		*p++ = ',';
	} while ((arg = p));
    }

    ret = syslinux_boot_linux(kernel_data, kernel_len, initramfs, NULL, newcmdline);

    printf("syslinux_boot_linux returned %d\n", ret);

    return 0;
}

/* sleep for sec seconds */
static int sl_sleep(lua_State * L)
{
    unsigned int sec = luaL_checkint(L, 1);
    sleep(sec);
    return 0;
}

/* sleep for msec milliseconds */
static int sl_msleep(lua_State * L)
{
    unsigned int msec = luaL_checkint(L, 1);
    msleep(msec);
    return 0;
}

static int sl_run_kernel_image(lua_State * L)
{
    const char *filename = luaL_checkstring(L, 1);
    const char *cmdline = luaL_checkstring(L, 2);
    uint32_t ipappend_flags = luaL_checkint(L, 3);
    uint32_t type = luaL_checkint(L, 4);

    syslinux_run_kernel_image(filename, cmdline, ipappend_flags, type);
    return 0;
}

static int sl_loadfile(lua_State * L)
{
    const char *filename = luaL_checkstring(L, 1);
    syslinux_file *file;

    void *file_data;
    size_t file_len;

    if (loadfile(filename, &file_data, &file_len)) {
	lua_pushstring(L, "Could not load file");
	lua_error(L);
    }

    file = malloc(sizeof(syslinux_file));
    strlcpy(file->name,filename,sizeof(syslinux_file));
    file->size = file_len;
    file->data = file_data;

    lua_pushlightuserdata(L, file);
    luaL_getmetatable(L, SYSLINUX_FILE);
    lua_setmetatable(L, -2);

    return 1;
}

static int sl_filesize(lua_State * L)
{
    const syslinux_file *file = luaL_checkudata(L, 1, SYSLINUX_FILE);

    lua_pushinteger(L, file->size);

    return 1;
}

static int sl_filename(lua_State * L)
{
    const syslinux_file *file = luaL_checkudata(L, 1, SYSLINUX_FILE);

    lua_pushstring(L, file->name);

    return 1;
}

static int sl_initramfs_init(lua_State * L)
{
    struct initramfs *initramfs;

    initramfs = initramfs_init();
    if (!initramfs)
	printf("Initializing initrd failed!\n");

    lua_pushlightuserdata(L, initramfs);
    luaL_getmetatable(L, SYSLINUX_FILE);
    lua_setmetatable(L, -2);

    return 1;
}

static int sl_initramfs_load_archive(lua_State * L)
{
    struct initramfs *initramfs = luaL_checkudata(L, 1, SYSLINUX_FILE);
    const char *filename = luaL_checkstring(L, 2);

    if (initramfs_load_archive(initramfs, filename)) {
	printf("failed!\n");
    }

    return 0;
}

static int sl_initramfs_add_file(lua_State * L)
{
    struct initramfs *initramfs = luaL_checkudata(L, 1, SYSLINUX_FILE);
    const char *filename = luaL_checkstring(L, 2);
    void *file_data = NULL;
    size_t file_len = 0;

    return initramfs_add_file(initramfs, file_data, file_len, file_len,
			      filename, 0, 0755);
}

static int sl_boot_it(lua_State * L)
{
    const syslinux_file *kernel = luaL_checkudata(L, 1, SYSLINUX_FILE);
    struct initramfs *initramfs = luaL_checkudata(L, 2, SYSLINUX_FILE);
    const char *cmdline = luaL_optstring(L, 3, "");
    uint32_t mem_limit = luaL_optint(L, 4, 0);
    uint16_t video_mode = luaL_optint(L, 5, 0);
    /* Preventing gcc to complain about unused variables */
    (void)video_mode;
    (void)mem_limit;

    return syslinux_boot_linux(kernel->data, kernel->size,
			       initramfs, NULL, (char *)cmdline);
}

static int sl_config_file(lua_State * L)
{
    const char *config_file = syslinux_config_file();
    lua_pushstring(L, config_file);
    return 1;
}

static int sl_reboot(lua_State * L)
{
    int warm_boot = luaL_optint(L, 1, 0);
    /* explicitly convert it to 1 or 0 */
    warm_boot = warm_boot? 1 : 0;
    syslinux_reboot(warm_boot);
    return 0;
}

static int sl_ipappend_strs(lua_State * L)
{
    int i;
    const struct syslinux_ipappend_strings *ip_strs = syslinux_ipappend_strings();
    lua_newtable(L);
    for (i = 0; i < ip_strs->count; i++) {
        lua_pushinteger(L, i + 1);
        lua_pushstring(L, ip_strs->ptr[i]);
        lua_settable(L,-3);
    }
    return 1;
}

static int sl_derivative(lua_State * L)
{
    const struct syslinux_version *sv;

    sv = syslinux_version();

    switch (sv->filesystem) {
    case SYSLINUX_FS_SYSLINUX:
	lua_pushstring(L, "SYSLINUX");
	break;
    case SYSLINUX_FS_PXELINUX:
	lua_pushstring(L, "PXELINUX");
	break;
    case SYSLINUX_FS_ISOLINUX:
	lua_pushstring(L, "ISOLINUX");
	break;
    case SYSLINUX_FS_UNKNOWN:
    default:
	lua_pushstring(L, "Unknown Syslinux derivative");
	break;
    }

    return 1;
}

static int sl_version(lua_State * L)
{
    const struct syslinux_version *sv;

    sv = syslinux_version();
    lua_pushstring(L, sv->version_string);

    return 1;
}

static int sl_get_key (lua_State * L)
{
    int timeout = luaL_checkint (L, 1);
    lua_pushinteger (L, get_key (stdin, timeout));
    return 1;
}

static int sl_KEY_CTRL (lua_State * L)
{
    lua_pushinteger (L, KEY_CTRL (luaL_checkint (L, 1)));
    return 1;
}

static const luaL_Reg syslinuxlib[] = {
    {"run_command", sl_run_command},
    {"run_default", sl_run_default},
    {"local_boot", sl_local_boot},
    {"final_cleanup", sl_final_cleanup},
    {"boot_linux", sl_boot_linux},
    {"run_kernel_image", sl_run_kernel_image},
    {"sleep", sl_sleep},
    {"msleep", sl_msleep},
    {"loadfile", sl_loadfile},
    {"filesize", sl_filesize},
    {"filename", sl_filename},
    {"initramfs_init", sl_initramfs_init},
    {"initramfs_load_archive", sl_initramfs_load_archive},
    {"initramfs_add_file", sl_initramfs_add_file},
    {"boot_it", sl_boot_it},
    {"config_file", sl_config_file},
    {"ipappend_strs", sl_ipappend_strs},
    {"reboot", sl_reboot},
    {"derivative", sl_derivative},
    {"version", sl_version},
    {"get_key", sl_get_key},
    {"KEY_CTRL", sl_KEY_CTRL},
    {NULL, NULL}
};

/* This defines a function that opens up your library. */

LUALIB_API int luaopen_syslinux(lua_State * L)
{

    luaL_newmetatable(L, SYSLINUX_FILE);

    luaL_newlib(L, syslinuxlib);

    lua_newtable (L);
#define export_key(x) lua_pushinteger (L, KEY_##x); lua_setfield (L, -2, #x);
    export_key (NONE);
    export_key (BACKSPACE);
    export_key (TAB);
    export_key (ENTER);
    export_key (ESC);
    export_key (DEL);
    export_key (F1);
    export_key (F2);
    export_key (F3);
    export_key (F4);
    export_key (F5);
    export_key (F6);
    export_key (F7);
    export_key (F8);
    export_key (F9);
    export_key (F10);
    export_key (F11);
    export_key (F12);
    export_key (UP);
    export_key (DOWN);
    export_key (LEFT);
    export_key (RIGHT);
    export_key (PGUP);
    export_key (PGDN);
    export_key (HOME);
    export_key (END);
    export_key (INSERT);
    export_key (DELETE);
    lua_setfield (L, -2, "KEY");

    return 1;
}
