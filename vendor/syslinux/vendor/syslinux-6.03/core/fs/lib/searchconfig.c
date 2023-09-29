#include <dprintf.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <core.h>
#include <fs.h>

__export char ConfigName[FILENAME_MAX];
__export char config_cwd[FILENAME_MAX];

/*
 * This searches for a specified set of filenames in a specified set
 * of directories.  If found, set the current working directory to
 * match.
 */
int search_dirs(struct com32_filedata *filedata,
		const char *search_directories[],
		const char *filenames[],
		char *realname)
{
    char namebuf[FILENAME_MAX];
    const char *sd, **sdp;
    const char *sf, **sfp;

    for (sdp = search_directories; (sd = *sdp); sdp++) {
	for (sfp = filenames; (sf = *sfp); sfp++) {
	    snprintf(namebuf, sizeof namebuf,
		     "%s%s%s",
		     sd, (*sd && sd[strlen(sd)-1] == '/') ? "" : "/",
		     sf);
	    if (realpath(realname, namebuf, FILENAME_MAX) == (size_t)-1)
		continue;
	    dprintf("Config search: %s\n", realname);
	    if (open_file(realname, O_RDONLY, filedata) >= 0) {
		chdir(sd);
		return 0;	/* Got it */
	    }
	}
    }

    return -1;
}
