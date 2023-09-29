#include <dprintf.h>
#include <stdio.h>
#include <string.h>
#include <sys/dirent.h>
#include <core.h>
#include <cache.h>
#include <disk.h>
#include <fs.h>
#include <stdlib.h>
#include "iso9660_fs.h"
#include "susp_rr.h"

/* Convert to lower case string */
static inline char iso_tolower(char c)
{
    if (c >= 'A' && c <= 'Z')
	c += 0x20;

    return c;
}

static struct inode *new_iso_inode(struct fs_info *fs)
{
    return alloc_inode(fs, 0, sizeof(struct iso9660_pvt_inode));
}

static inline struct iso_sb_info *ISO_SB(struct fs_info *fs)
{
    return fs->fs_info;
}

static size_t iso_convert_name(char *dst, const char *src, int len)
{
    char *p = dst;
    char c;
    
    if (len == 1) {
	switch (*src) {
	case 1:
	    *p++ = '.';
	    /* fall through */
	case 0:
	    *p++ = '.';
	    goto done;
	default:
	    /* nothing special */
	    break;
	}
    }

    while (len-- && (c = *src++)) {
	if (c == ';')	/* Remove any filename version suffix */
	    break;
	*p++ = iso_tolower(c);
    }
    
    /* Then remove any terminal dots */
    while (p > dst+1 && p[-1] == '.')
	p--;

done:
    *p = '\0';
    return p - dst;
}

/* 
 * Unlike strcmp, it does return 1 on match, or reutrn 0 if not match.
 */
static bool iso_compare_name(const char *de_name, size_t len,
			     const char *file_name)
{
    char iso_file_name[256];
    char *p = iso_file_name;
    char c1, c2;
    int i;
    
    i = iso_convert_name(iso_file_name, de_name, len);
    (void)i;
    dprintf("Compare: \"%s\" to \"%s\" (len %zu)\n",
	    file_name, iso_file_name, i);

    do {
	c1 = *p++;
	c2 = iso_tolower(*file_name++);

	/* compare equal except for case? */
	if (c1 != c2)
	    return false;
    } while (c1);

    return true;
}

/*
 * Find a entry in the specified dir with name _dname_.
 */
static const struct iso_dir_entry *
iso_find_entry(const char *dname, struct inode *inode)
{
    struct fs_info *fs = inode->fs;
    block_t dir_block = PVT(inode)->lba;
    int i = 0, offset = 0;
    const char *de_name;
    int de_name_len, de_len, rr_name_len, ret;
    const struct iso_dir_entry *de;
    const char *data = NULL;
    char *rr_name = NULL;

    dprintf("iso_find_entry: \"%s\"\n", dname);
    
    while (1) {
	if (!data) {
	    dprintf("Getting block %d from block %llu\n", i, dir_block);
	    if (++i > inode->blocks)
		return NULL;	/* End of directory */
	    data = get_cache(fs->fs_dev, dir_block++);
	    offset = 0;
	}

	de = (const struct iso_dir_entry *)(data + offset);
	de_len = de->length;
	offset += de_len;
	
	/* Make sure we have a full directory entry */
	if (de_len < 33 || offset > BLOCK_SIZE(fs)) {
	    /*
	     * Zero = end of sector, or corrupt directory entry
	     *
	     * ECMA-119:1987 6.8.1.1: "Each Directory Record shall end
	     * in the Logical Sector in which it begins.
	     */
	    data = NULL;
	    continue;
	}
	
	/* Try to get Rock Ridge name */
	ret = susp_rr_get_nm(fs, (char *) de, &rr_name, &rr_name_len);
	if (ret > 0) {
	    if (strcmp(rr_name, dname) == 0) {
		dprintf("Found (by RR name).\n");
		free(rr_name);
		return de;
	    }
	    free(rr_name);
	    rr_name = NULL;
	    continue; /* Rock Ridge was valid and did not match */
	}

	/* Fall back to ISO name */
	de_name_len = de->name_len;
	de_name = de->name;
	if (iso_compare_name(de_name, de_name_len, dname)) {
	    dprintf("Found (by ISO name).\n");
	    return de;
	}
    }
}

static inline enum dirent_type get_inode_mode(uint8_t flags)
{
    return (flags & 0x02) ? DT_DIR : DT_REG;
}

static struct inode *iso_get_inode(struct fs_info *fs,
				   const struct iso_dir_entry *de)
{
    struct inode *inode = new_iso_inode(fs);
    int blktosec = BLOCK_SHIFT(fs) - SECTOR_SHIFT(fs);

    if (!inode)
	return NULL;

    dprintf("Getting inode for: %.*s\n", de->name_len, de->name);

    inode->mode   = get_inode_mode(de->flags);
    inode->size   = de->size_le;
    PVT(inode)->lba = de->extent_le;
    inode->blocks = (inode->size + BLOCK_SIZE(fs) - 1) >> BLOCK_SHIFT(fs);

    /* We have a single extent for all data */
    inode->next_extent.pstart = (sector_t)de->extent_le << blktosec;
    inode->next_extent.len    = (sector_t)inode->blocks << blktosec;

    return inode;
}

static struct inode *iso_iget_root(struct fs_info *fs)
{
    const struct iso_dir_entry *root = &ISO_SB(fs)->root;

    return iso_get_inode(fs, root);
}

static struct inode *iso_iget(const char *dname, struct inode *parent)
{
    const struct iso_dir_entry *de;
    
    dprintf("iso_iget %p %s\n", parent, dname);

    de = iso_find_entry(dname, parent);
    if (!de)
	return NULL;
    
    return iso_get_inode(parent->fs, de);
}

static int iso_readdir(struct file *file, struct dirent *dirent)
{
    struct fs_info *fs = file->fs;
    struct inode *inode = file->inode;
    const struct iso_dir_entry *de;
    const char *data = NULL;
    char *rr_name = NULL;
    int name_len, ret;
    
    while (1) {
	size_t offset = file->offset & (BLOCK_SIZE(fs) - 1);

	if (!data) {
	    uint32_t i = file->offset >> BLOCK_SHIFT(fs);
	    if (i >= inode->blocks)
		return -1;
	    data = get_cache(fs->fs_dev, PVT(inode)->lba + i);
	}
	de = (const struct iso_dir_entry *)(data + offset);
	
	if (de->length < 33 || offset + de->length > BLOCK_SIZE(fs)) {
	    file->offset = (file->offset + BLOCK_SIZE(fs))
		& ~(BLOCK_SIZE(fs) - 1); /* Start of the next block */
	    data = NULL;
	    continue;
	}
	break;
    }
    
    dirent->d_ino = 0;           /* Inode number is invalid to ISO fs */
    dirent->d_off = file->offset;
    dirent->d_type = get_inode_mode(de->flags);

    /* Try to get Rock Ridge name */
    ret = susp_rr_get_nm(fs, (char *) de, &rr_name, &name_len);
    if (ret > 0) {
	memcpy(dirent->d_name, rr_name, name_len + 1);
	free(rr_name);
	rr_name = NULL;
    } else {
	name_len = iso_convert_name(dirent->d_name, de->name, de->name_len);
    }

    dirent->d_reclen = offsetof(struct dirent, d_name) + 1 + name_len;

    file->offset += de->length;  /* Update for next reading */
    
    return 0;
}

/* Load the config file, return 1 if failed, or 0 */
static int iso_open_config(struct com32_filedata *filedata)
{
    static const char *search_directories[] = {
	"/boot/isolinux", 
	"/isolinux",
	"/boot/syslinux", 
	"/syslinux", 
	"/",
	NULL
    };
    static const char *filenames[] = {
	"isolinux.cfg",
	"syslinux.cfg",
	NULL
    };

    return search_dirs(filedata, search_directories, filenames, ConfigName);
}

static int iso_fs_init(struct fs_info *fs)
{
    struct iso_sb_info *sbi;
    char pvd[2048];		/* Primary Volume Descriptor */
    uint32_t pvd_lba;
    struct disk *disk = fs->fs_dev->disk;
    int blktosec;

    sbi = malloc(sizeof(*sbi));
    if (!sbi) {
	malloc_error("iso_sb_info structure");
	return 1;
    }
    fs->fs_info = sbi;

    /* 
     * XXX: handling iso9660 in hybrid mode on top of a 4K-logical disk
     * will really, really hurt...
     */
    fs->sector_shift = fs->fs_dev->disk->sector_shift;
    fs->block_shift  = 11;	/* A CD-ROM block is always 2K */
    fs->sector_size  = 1 << fs->sector_shift;
    fs->block_size   = 1 << fs->block_shift;
    blktosec = fs->block_shift - fs->sector_shift;

    pvd_lba = iso_boot_info.pvd;
    if (!pvd_lba)
	pvd_lba = 16;		/* Default if not otherwise defined */

    disk->rdwr_sectors(disk, pvd, (sector_t)pvd_lba << blktosec,
		       1 << blktosec, false);
    memcpy(&sbi->root, pvd + ROOT_DIR_OFFSET, sizeof(sbi->root));

    /* Initialize the cache */
    cache_init(fs->fs_dev, fs->block_shift);

    /* Check for SP and ER in the first directory record of the root directory.
       Set sbi->susp_skip and enable sbi->do_rr as appropriate.
    */
    susp_rr_check_signatures(fs, 1);

    return fs->block_shift;
}


const struct fs_ops iso_fs_ops = {
    .fs_name       = "iso",
    .fs_flags      = FS_USEMEM | FS_THISIND,
    .fs_init       = iso_fs_init,
    .searchdir     = NULL, 
    .getfssec      = generic_getfssec,
    .close_file    = generic_close_file,
    .mangle_name   = generic_mangle_name,
    .open_config   = iso_open_config,
    .iget_root     = iso_iget_root,
    .iget          = iso_iget,
    .readdir       = iso_readdir,
    .next_extent   = no_next_extent,
    .fs_uuid       = NULL,
};
