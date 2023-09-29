#include <sys/file.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dprintf.h>
#include <syslinux/sysappend.h>
#include "core.h"
#include "dev.h"
#include "fs.h"
#include "cache.h"

/* The currently mounted filesystem */
__export struct fs_info *this_fs = NULL;		/* Root filesystem */

/* Actual file structures (we don't have malloc yet...) */
__export struct file files[MAX_OPEN];

/* Symlink hard limits */
#define MAX_SYMLINK_CNT	20
#define MAX_SYMLINK_BUF 4096

/*
 * Get a new inode structure
 */
struct inode *alloc_inode(struct fs_info *fs, uint32_t ino, size_t data)
{
    struct inode *inode = zalloc(sizeof(struct inode) + data);
    if (inode) {
	inode->fs = fs;
	inode->ino = ino;
	inode->refcnt = 1;
    }
    return inode;
}

/*
 * Free a refcounted inode
 */
void put_inode(struct inode *inode)
{
    while (inode) {
	struct inode *dead = inode;
	int refcnt = --(dead->refcnt);
	dprintf("put_inode %p name %s refcnt %u\n", dead, dead->name, refcnt);
	if (refcnt)
	    break;		/* We still have references */
	inode = dead->parent;
	if (dead->name)
	    free((char *)dead->name);
	free(dead);
    }
}

/*
 * Get an empty file structure
 */
static struct file *alloc_file(void)
{
    int i;
    struct file *file = files;

    for (i = 0; i < MAX_OPEN; i++) {
	if (!file->fs)
	    return file;
	file++;
    }

    return NULL;
}

/*
 * Close and free a file structure
 */
static inline void free_file(struct file *file)
{
    memset(file, 0, sizeof *file);
}

__export void _close_file(struct file *file)
{
    if (file->fs)
	file->fs->fs_ops->close_file(file);
    free_file(file);
}

/*
 * Find and open the configuration file
 */
__export int open_config(void)
{
    int fd, handle;
    struct file_info *fp;

    fd = opendev(&__file_dev, NULL, O_RDONLY);
    if (fd < 0)
	return -1;

    fp = &__file_info[fd];

    handle = this_fs->fs_ops->open_config(&fp->i.fd);
    if (handle < 0) {
	close(fd);
	errno = ENOENT;
	return -1;
    }

    fp->i.offset = 0;
    fp->i.nbytes = 0;

    return fd;
}

__export void mangle_name(char *dst, const char *src)
{
    this_fs->fs_ops->mangle_name(dst, src);
}

size_t pmapi_read_file(uint16_t *handle, void *buf, size_t sectors)
{
    bool have_more;
    size_t bytes_read;
    struct file *file;

    file = handle_to_file(*handle);
    bytes_read = file->fs->fs_ops->getfssec(file, buf, sectors, &have_more);

    /*
     * If we reach EOF, the filesystem driver will have already closed
     * the underlying file... this really should be cleaner.
     */
    if (!have_more) {
	_close_file(file);
	*handle = 0;
    }

    return bytes_read;
}

int searchdir(const char *name, int flags)
{
    static char root_name[] = "/";
    struct file *file;
    char *path, *inode_name, *next_inode_name;
    struct inode *tmp, *inode = NULL;
    int symlink_count = MAX_SYMLINK_CNT;

    dprintf("searchdir: %s  root: %p  cwd: %p\n",
	    name, this_fs->root, this_fs->cwd);

    if (!(file = alloc_file()))
	goto err_no_close;
    file->fs = this_fs;

    /* if we have ->searchdir method, call it */
    if (file->fs->fs_ops->searchdir) {
	file->fs->fs_ops->searchdir(name, flags, file);

	if (file->inode)
	    return file_to_handle(file);
	else
	    goto err;
    }

    /* else, try the generic-path-lookup method */

    /* Copy the path */
    path = strdup(name);
    if (!path) {
	dprintf("searchdir: Couldn't copy path\n");
	goto err_path;
    }

    /* Work with the current directory, by default */
    inode = get_inode(this_fs->cwd);
    if (!inode) {
	dprintf("searchdir: Couldn't use current directory\n");
	goto err_curdir;
    }

    for (inode_name = path; inode_name; inode_name = next_inode_name) {
	/* Root directory? */
	if (inode_name[0] == '/') {
	    next_inode_name = inode_name + 1;
	    inode_name = root_name;
	} else {
	    /* Find the next inode name */
	    next_inode_name = strchr(inode_name + 1, '/');
	    if (next_inode_name) {
		/* Terminate the current inode name and point to next */
		*next_inode_name++ = '\0';
	    }
	}
	if (next_inode_name) {
	    /* Advance beyond redundant slashes */
	    while (*next_inode_name == '/')
		next_inode_name++;

	    /* Check if we're at the end */
	    if (*next_inode_name == '\0')
		next_inode_name = NULL;
	}
	dprintf("searchdir: inode_name: %s\n", inode_name);
	if (next_inode_name)
	    dprintf("searchdir: Remaining: %s\n", next_inode_name);

	/* Root directory? */
	if (inode_name[0] == '/') {
	    /* Release any chain that's already been established */
	    put_inode(inode);
	    inode = get_inode(this_fs->root);
	    continue;
	}

	/* Current directory? */
	if (!strncmp(inode_name, ".", sizeof "."))
	    continue;

	/* Parent directory? */
	if (!strncmp(inode_name, "..", sizeof "..")) {
	    /* If there is no parent, just ignore it */
	    if (!inode->parent)
		continue;

	    /* Add a reference to the parent so we can release the child */
	    tmp = get_inode(inode->parent);

	    /* Releasing the child will drop the parent back down to 1 */
	    put_inode(inode);

	    inode = tmp;
	    continue;
	}

	/* Anything else */
	tmp = inode;
	inode = this_fs->fs_ops->iget(inode_name, inode);
	if (!inode) {
	    /* Failure.  Release the chain */
	    put_inode(tmp);
	    break;
	}

	/* Sanity-check */
	if (inode->parent && inode->parent != tmp) {
	    dprintf("searchdir: iget returned a different parent\n");
	    put_inode(inode);
	    inode = NULL;
	    put_inode(tmp);
	    break;
	}
	inode->parent = tmp;
	inode->name = strdup(inode_name);
	dprintf("searchdir: path component: %s\n", inode->name);

	/* Symlink handling */
	if (inode->mode == DT_LNK) {
	    char *new_path;
	    int new_len, copied;

	    /* target path + NUL */
	    new_len = inode->size + 1;

	    if (next_inode_name) {
		/* target path + slash + remaining + NUL */
		new_len += strlen(next_inode_name) + 1;
	    }

	    if (!this_fs->fs_ops->readlink ||
		/* limit checks */
		--symlink_count == 0 ||
		new_len > MAX_SYMLINK_BUF)
		goto err_new_len;

	    new_path = malloc(new_len);
	    if (!new_path)
		goto err_new_path;

	    copied = this_fs->fs_ops->readlink(inode, new_path);
	    if (copied <= 0)
		goto err_copied;
	    new_path[copied] = '\0';
	    dprintf("searchdir: Symlink: %s\n", new_path);

	    if (next_inode_name) {
		new_path[copied] = '/';
		strcpy(new_path + copied + 1, next_inode_name);
		dprintf("searchdir: New path: %s\n", new_path);
	    }

	    free(path);
	    path = next_inode_name = new_path;

            /* Add a reference to the parent so we can release the child */
            tmp = get_inode(inode->parent);

            /* Releasing the child will drop the parent back down to 1 */
            put_inode(inode);

            inode = tmp;
	    continue;
err_copied:
	    free(new_path);
err_new_path:
err_new_len:
	    put_inode(inode);
	    inode = NULL;
	    break;
	}

	/* If there's more to process, this should be a directory */
	if (next_inode_name && inode->mode != DT_DIR) {
	    dprintf("searchdir: Expected a directory\n");
	    put_inode(inode);
	    inode = NULL;
	    break;
	}
    }
err_curdir:
    free(path);
err_path:
    if (!inode) {
	dprintf("searchdir: Not found\n");
	goto err;
    }

    file->inode  = inode;
    file->offset = 0;

    return file_to_handle(file);

err:
    dprintf("serachdir: error seraching file %s\n", name);
    _close_file(file);
err_no_close:
    return -1;
}

__export int open_file(const char *name, int flags, struct com32_filedata *filedata)
{
    int rv;
    struct file *file;
    char mangled_name[FILENAME_MAX];

    dprintf("open_file %s\n", name);

    mangle_name(mangled_name, name);
    rv = searchdir(mangled_name, flags);

    if (rv < 0)
	return rv;

    file = handle_to_file(rv);

    if (file->inode->mode != DT_REG) {
	_close_file(file);
	return -1;
    }

    filedata->size	= file->inode->size;
    filedata->blocklg2	= SECTOR_SHIFT(file->fs);
    filedata->handle	= rv;

    return rv;
}

__export void close_file(uint16_t handle)
{
    struct file *file;

    if (handle) {
	file = handle_to_file(handle);
	_close_file(file);
    }
}

__export char *fs_uuid(void)
{
    if (!this_fs || !this_fs->fs_ops || !this_fs->fs_ops->fs_uuid)
	return NULL;
    return this_fs->fs_ops->fs_uuid(this_fs);
}

/*
 * it will do:
 *    initialize the memory management function;
 *    set up the vfs fs structure;
 *    initialize the device structure;
 *    invoke the fs-specific init function;
 *    initialize the cache if we need one;
 *    finally, get the current inode for relative path looking.
 *
 * ops is a ptr list for several fs_ops
 */
__bss16 uint16_t SectorSize, SectorShift;

void fs_init(const struct fs_ops **ops, void *priv)
{
    static struct fs_info fs;	/* The actual filesystem buffer */
    int blk_shift = -1;
    struct device *dev = NULL;

    /* Default name for the root directory */
    fs.cwd_name[0] = '/';

    while ((blk_shift < 0) && *ops) {
	/* set up the fs stucture */
	fs.fs_ops = *ops;

	/*
	 * This boldly assumes that we don't mix FS_NODEV filesystems
	 * with FS_DEV filesystems...
	 */
	if (fs.fs_ops->fs_flags & FS_NODEV) {
	    fs.fs_dev = NULL;
	} else {
	    if (!dev)
		dev = device_init(priv);
	    fs.fs_dev = dev;
	}
	/* invoke the fs-specific init code */
	blk_shift = fs.fs_ops->fs_init(&fs);
	ops++;
    }
    if (blk_shift < 0) {
	printf("No valid file system found!\n");
	while (1)
		;
    }
    this_fs = &fs;

    /* initialize the cache only if it wasn't already initialized
     * by the fs driver */
    if (fs.fs_dev && fs.fs_dev->cache_data && !fs.fs_dev->cache_init)
        cache_init(fs.fs_dev, blk_shift);

    /* start out in the root directory */
    if (fs.fs_ops->iget_root) {
	fs.root = fs.fs_ops->iget_root(&fs);
	fs.cwd = get_inode(fs.root);
	dprintf("init: root inode %p, cwd inode %p\n", fs.root, fs.cwd);
    }

    if (fs.fs_ops->chdir_start) {
	    if (fs.fs_ops->chdir_start() < 0)
		    printf("Failed to chdir to start directory\n");
    }

    SectorShift = fs.sector_shift;
    SectorSize  = fs.sector_size;

    /* Add FSUUID=... string to cmdline */
    sysappend_set_fs_uuid();

}
