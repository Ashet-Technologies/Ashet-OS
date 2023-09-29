#include <string.h>
#include "fs.h"

__export char *core_getcwd(char *buf, size_t size)
{
    char *ret = NULL;

    if((buf != NULL) && (strlen(this_fs->cwd_name) < size)) {
        strcpy(buf, this_fs->cwd_name);
        ret = buf;
    }
    return ret;
}
