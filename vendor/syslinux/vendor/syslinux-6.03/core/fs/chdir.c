#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <dprintf.h>
#include <fcntl.h>
#include "fs.h"
#include "cache.h"

/*
 * Convert a relative pathname to an absolute pathname
 * In the future this might also resolve symlinks...
 */
void pm_realpath(com32sys_t *regs)
{
    const char *src = MK_PTR(regs->ds, regs->esi.w[0]);
    char       *dst = MK_PTR(regs->es, regs->edi.w[0]);

    realpath(dst, src, FILENAME_MAX);
}

static size_t copy_string(char *buf, size_t ix, size_t bufsize, const char *src)
{
    char c;

    while ((c = *src++)) {
	if (ix+1 < bufsize)
	    buf[ix] = c;
	ix++;
    }

    if (ix < bufsize)
	buf[ix] = '\0';

    return ix;
}

static size_t generic_inode_to_path(struct inode *inode, char *dst, size_t bufsize)
{
    size_t s = 0;

    dprintf("inode %p name %s\n", inode, inode->name);

    if (inode->parent) {
	if (!inode->name)	/* Only the root should have no name */
	    return -1;

	s = generic_inode_to_path(inode->parent, dst, bufsize);
	if (s == (size_t)-1)
	    return s;		/* Error! */

	s = copy_string(dst, s, bufsize, "/");
	s = copy_string(dst, s, bufsize, inode->name);
    }

    return s;
}

__export size_t realpath(char *dst, const char *src, size_t bufsize)
{
    int rv;
    struct file *file;
    size_t s;

    dprintf("realpath: input: %s\n", src);

    if (this_fs->fs_ops->realpath) {
	s = this_fs->fs_ops->realpath(this_fs, dst, src, bufsize);
    } else {
	rv = searchdir(src, O_RDONLY);
	if (rv < 0) {
	    dprintf("realpath: searchpath failure\n");
	    return -1;
	}

	file = handle_to_file(rv);
	s = generic_inode_to_path(file->inode, dst, bufsize);
	if (s == 0)
	    s = copy_string(dst, 0, bufsize, "/");

	_close_file(file);
    }

    dprintf("realpath: output: %s\n", dst);
    return s;
}

__export int chdir(const char *src)
{
    int rv;
    struct file *file;
    char cwd_buf[CURRENTDIR_MAX];
    size_t s;

    dprintf("chdir: from %s (inode %p) add %s\n",
	    this_fs->cwd_name, this_fs->cwd, src);

    if (this_fs->fs_ops->chdir)
	return this_fs->fs_ops->chdir(this_fs, src);

    /* Otherwise it is a "conventional filesystem" */
    rv = searchdir(src, O_RDONLY|O_DIRECTORY);
    if (rv < 0)
	return rv;

    file = handle_to_file(rv);
    if (file->inode->mode != DT_DIR) {
	_close_file(file);
	return -1;
    }

    put_inode(this_fs->cwd);
    this_fs->cwd = get_inode(file->inode);
    _close_file(file);

    /* Save the current working directory */
    s = generic_inode_to_path(this_fs->cwd, cwd_buf, CURRENTDIR_MAX-1);

    /* Make sure the cwd_name ends in a slash, it's supposed to be a prefix */
    if (s < 1 || cwd_buf[s-1] != '/')
	cwd_buf[s++] = '/';

    if (s >= CURRENTDIR_MAX)
	s = CURRENTDIR_MAX - 1;

    cwd_buf[s++] = '\0';
    memcpy(this_fs->cwd_name, cwd_buf, s);

    dprintf("chdir: final %s (inode %p)\n",
	    this_fs->cwd_name, this_fs->cwd);

    return 0;
}
