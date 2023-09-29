#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/dirent.h>
#include "fs.h"
#include "core.h"

/* 
 * Open a directory
 */
__export DIR *opendir(const char *path)
{
    int rv;
    struct file *file;

    rv = searchdir(path, O_RDONLY|O_DIRECTORY);
    if (rv < 0)
	return NULL;

    file = handle_to_file(rv);

    if (file->inode->mode != DT_DIR) {
	_close_file(file);
	return NULL;
    }

    return (DIR *)file;
}

/*
 * Read one directory entry at one time. 
 */
__export struct dirent *readdir(DIR *dir)
{
    static struct dirent buf;
    struct file *dd_dir = (struct file *)dir;
    int rv = -1;
    
    if (dd_dir) {
        if (dd_dir->fs->fs_ops->readdir) {
	    rv = dd_dir->fs->fs_ops->readdir(dd_dir, &buf);
        }
    }

    return rv < 0 ? NULL : &buf;
}

/*
 * Close a directory
 */
__export int closedir(DIR *dir)
{
    struct file *dd_dir = (struct file *)dir;
    _close_file(dd_dir);
    return 0;
}


