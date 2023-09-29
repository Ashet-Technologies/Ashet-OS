#include <dprintf.h>
#include <stdio.h>
#include <string.h>
#include <core.h>
#include <fs.h>

/*
 * Standard version of load_config for extlinux/syslinux filesystems.
 *
 * This searches for extlinux.conf and syslinux.cfg in the install
 * directory, followed by a set of fallback directories.  If found,
 * set the current working directory to match.
 */
int generic_open_config(struct com32_filedata *filedata)
{
    static const char *search_directories[] = {
	NULL,			/* CurrentDirName */
	"/boot/syslinux",
	"/syslinux",
	"/",
	NULL
    };
    static const char *filenames[] = {
	"extlinux.conf",
	"syslinux.cfg",
	NULL
    };

    search_directories[0] = CurrentDirName;

    dprintf("CurrentDirName: \"%s\"\n", CurrentDirName);

    return search_dirs(filedata, search_directories, filenames, ConfigName);
}
