#include <dprintf.h>
#include <stdio.h>
#include <string.h>
#include <sys/dirent.h>
#include <minmax.h>
#include "cache.h"
#include "core.h"
#include "disk.h"
#include "fs.h"
#include "ext2_fs.h"

/*
 * Convert an ext2 file type to the global values
 */
static enum dirent_type ext2_cvt_type(unsigned int d_file_type)
{
    static const enum dirent_type inode_type[] = {
	DT_UNKNOWN, DT_REG, DT_DIR, DT_CHR,
	DT_BLK, DT_FIFO, DT_SOCK, DT_LNK,
    };

    if (d_file_type > sizeof inode_type / sizeof *inode_type)
	return DT_UNKNOWN;
    else
	return inode_type[d_file_type];
}

/*
 * get the group's descriptor of group_num
 */
static const struct ext2_group_desc *
ext2_get_group_desc(struct fs_info *fs, uint32_t group_num)
{
    struct ext2_sb_info *sbi = EXT2_SB(fs);
    uint32_t desc_block, desc_index;
    const struct ext2_group_desc *desc_data_block;

    if (group_num >= sbi->s_groups_count) {
	printf ("ext2_get_group_desc"
		"block_group >= groups_count - "
		"block_group = %d, groups_count = %d",
		group_num, sbi->s_groups_count);

	return NULL;
    }

    desc_block = group_num / sbi->s_desc_per_block;
    desc_index = group_num % sbi->s_desc_per_block;

    desc_block += sbi->s_first_data_block + 1;

    desc_data_block = get_cache(fs->fs_dev, desc_block);
    return &desc_data_block[desc_index];
}

/*
 * Unlike strncmp, ext2_match_entry returns 1 for success, 0 for failure.
 */
static inline bool ext2_match_entry(const char *name, size_t len,
                                    const struct ext2_dir_entry * de)
{
    if (!de->d_inode)
        return false;
    if (len != de->d_name_len)
	return false;
    return !memcmp(name, de->d_name, len);
}


/*
 * p is at least 6 bytes before the end of page
 */
static inline struct ext2_dir_entry *ext2_next_entry(struct ext2_dir_entry *p)
{
    return (struct ext2_dir_entry *)((char*)p + p->d_rec_len);
}

/*
 * Map a logical sector and load it into the cache
 */
static const void *
ext2_get_cache(struct inode *inode, block_t lblock)
{
    block_t pblock = ext2_bmap(inode, lblock, NULL);
    return get_cache(inode->fs->fs_dev, pblock);
}

/*
 * find a dir entry, return it if found, or return NULL.
 */
static const struct ext2_dir_entry *
ext2_find_entry(struct fs_info *fs, struct inode *inode, const char *dname)
{
    block_t index = 0;
    uint32_t i = 0, offset, maxoffset;
    const struct ext2_dir_entry *de;
    const char *data;
    size_t dname_len = strlen(dname);

    while (i < inode->size) {
	data = ext2_get_cache(inode, index++);
	offset = 0;
	maxoffset =  min(BLOCK_SIZE(fs), i-inode->size);

	/* The smallest possible size is 9 bytes */
	while (offset < maxoffset-8) {
	    de = (const struct ext2_dir_entry *)(data + offset);
	    if (de->d_rec_len > maxoffset - offset)
		break;

	    if (ext2_match_entry(dname, dname_len, de))
		return de;

	    offset += de->d_rec_len;
	}
	i += BLOCK_SIZE(fs);
    }

    return NULL;
}

static const struct ext2_inode *
ext2_get_inode(struct fs_info *fs, int inr)
{
    const struct ext2_group_desc *desc;
    const char *data;
    uint32_t inode_group, inode_offset;
    uint32_t block_num, block_off;

    inr--;
    inode_group  = inr / EXT2_INODES_PER_GROUP(fs);
    inode_offset = inr % EXT2_INODES_PER_GROUP(fs);
    desc = ext2_get_group_desc(fs, inode_group);
    if (!desc)
	return NULL;

    block_num = desc->bg_inode_table +
	inode_offset / EXT2_INODES_PER_BLOCK(fs);
    block_off = inode_offset % EXT2_INODES_PER_BLOCK(fs);

    data = get_cache(fs->fs_dev, block_num);

    return (const struct ext2_inode *)
	(data + block_off * EXT2_SB(fs)->s_inode_size);
}

static void fill_inode(struct inode *inode, const struct ext2_inode *e_inode)
{
    inode->mode    = IFTODT(e_inode->i_mode);
    inode->size    = e_inode->i_size;
    inode->atime   = e_inode->i_atime;
    inode->ctime   = e_inode->i_ctime;
    inode->mtime   = e_inode->i_mtime;
    inode->dtime   = e_inode->i_dtime;
    inode->blocks  = e_inode->i_blocks;
    inode->flags   = e_inode->i_flags;
    inode->file_acl = e_inode->i_file_acl;
    memcpy(PVT(inode)->i_block, e_inode->i_block, sizeof PVT(inode)->i_block);
}

static struct inode *ext2_iget_by_inr(struct fs_info *fs, uint32_t inr)
{
    const struct ext2_inode *e_inode;
    struct inode *inode;

    e_inode = ext2_get_inode(fs, inr);
    if (!e_inode)
	return NULL;

    if (!(inode = alloc_inode(fs, inr, sizeof(struct ext2_pvt_inode))))
	return NULL;
    fill_inode(inode, e_inode);

    return inode;
}

static struct inode *ext2_iget_root(struct fs_info *fs)
{
    return ext2_iget_by_inr(fs, EXT2_ROOT_INO);
}

static struct inode *ext2_iget(const char *dname, struct inode *parent)
{
    const struct ext2_dir_entry *de;
    struct fs_info *fs = parent->fs;

    de = ext2_find_entry(fs, parent, dname);
    if (!de)
	return NULL;
    
    return ext2_iget_by_inr(fs, de->d_inode);
}

/*
 * Read the entire contents of an inode into a memory buffer
 */
static int cache_get_file(struct inode *inode, void *buf, size_t bytes)
{
    struct fs_info *fs = inode->fs;
    size_t block_size = BLOCK_SIZE(fs);
    uint32_t index = 0;		/* Logical block number */
    size_t chunk;
    const char *data;
    char *p = buf;

    if (inode->size > bytes)
	bytes = inode->size;

    while (bytes) {
	chunk = min(bytes, block_size);
	data = ext2_get_cache(inode, index++);
	memcpy(p, data, chunk);

	bytes -= chunk;
	p += chunk;
    }

    return 0;
}
	
static int ext2_readlink(struct inode *inode, char *buf)
{
    struct fs_info *fs = inode->fs;
    int sec_per_block = 1 << (fs->block_shift - fs->sector_shift);
    bool fast_symlink;

    if (inode->size > BLOCK_SIZE(fs))
	return -1;		/* Error! */

    fast_symlink = (inode->file_acl ? sec_per_block : 0) == inode->blocks;
    if (fast_symlink)
	memcpy(buf, PVT(inode)->i_block, inode->size);
    else
	cache_get_file(inode, buf, inode->size);

    return inode->size;
}

/*
 * Read one directory entry at a time
 */
static int ext2_readdir(struct file *file, struct dirent *dirent)
{
    struct fs_info *fs = file->fs;
    struct inode *inode = file->inode;
    const struct ext2_dir_entry *de;
    const char *data;
    block_t index = file->offset >> fs->block_shift;

    if (file->offset >= inode->size)
	return -1;		/* End of file */

    data = ext2_get_cache(inode, index);
    de = (const struct ext2_dir_entry *)
	(data + (file->offset & (BLOCK_SIZE(fs) - 1)));

    dirent->d_ino = de->d_inode;
    dirent->d_off = file->offset;
    dirent->d_reclen = offsetof(struct dirent, d_name) + de->d_name_len + 1;
    dirent->d_type = ext2_cvt_type(de->d_file_type);
    memcpy(dirent->d_name, de->d_name, de->d_name_len);
    dirent->d_name[de->d_name_len] = '\0';

    file->offset += de->d_rec_len;  /* Update for next reading */

    return 0;
}

/*
 * init. the fs meta data, return the block size bits.
 */
static int ext2_fs_init(struct fs_info *fs)
{
    struct disk *disk = fs->fs_dev->disk;
    struct ext2_sb_info *sbi;
    struct ext2_super_block sb;
    struct cache *cs;

    /* read the super block */
    disk->rdwr_sectors(disk, &sb, 2, 2, 0);

    /* check if it is ext2, since we also support btrfs now */
    if (sb.s_magic != EXT2_SUPER_MAGIC)
	return -1;

    sbi = malloc(sizeof(*sbi));
    if (!sbi) {
	malloc_error("ext2_sb_info structure");
	return -1;
    }
    fs->fs_info = sbi;

    if (sb.s_magic != EXT2_SUPER_MAGIC) {
	printf("ext2 mount error: it's not a EXT2/3/4 file system!\n");
	return 0;
    }

    fs->sector_shift = disk->sector_shift;
    fs->block_shift  = sb.s_log_block_size + 10;
    fs->sector_size  = 1 << fs->sector_shift;
    fs->block_size   = 1 << fs->block_shift;

    sbi->s_inodes_per_group = sb.s_inodes_per_group;
    sbi->s_blocks_per_group = sb.s_blocks_per_group;
    sbi->s_inodes_per_block = BLOCK_SIZE(fs) / sb.s_inode_size;
    if (sb.s_desc_size < sizeof(struct ext2_group_desc))
	sb.s_desc_size = sizeof(struct ext2_group_desc);
    sbi->s_desc_per_block   = BLOCK_SIZE(fs) / sb.s_desc_size;
    sbi->s_groups_count     = (sb.s_blocks_count - sb.s_first_data_block
			       + EXT2_BLOCKS_PER_GROUP(fs) - 1)
	                      / EXT2_BLOCKS_PER_GROUP(fs);
    sbi->s_first_data_block = sb.s_first_data_block;
    sbi->s_inode_size = sb.s_inode_size;

    /* Volume UUID */
    memcpy(sbi->s_uuid, sb.s_uuid, sizeof(sbi->s_uuid));

    /* Initialize the cache, and force block zero to all zero */
    cache_init(fs->fs_dev, fs->block_shift);
    cs = _get_cache_block(fs->fs_dev, 0);
    memset(cs->data, 0, fs->block_size);
    cache_lock_block(cs);

    return fs->block_shift;
}

#define EXT2_UUID_LEN (4 + 4 + 1 + 4 + 1 + 4 + 1 + 4 + 1 + 4 + 4 + 4 + 1)
static char *ext2_fs_uuid(struct fs_info *fs)
{
    char *uuid = NULL;

    uuid = malloc(EXT2_UUID_LEN);
    if (!uuid)
	return NULL;

    if (snprintf(uuid, EXT2_UUID_LEN,
                  "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
	          EXT2_SB(fs)->s_uuid[0],
	          EXT2_SB(fs)->s_uuid[1],
	          EXT2_SB(fs)->s_uuid[2],
	          EXT2_SB(fs)->s_uuid[3],
	          EXT2_SB(fs)->s_uuid[4],
	          EXT2_SB(fs)->s_uuid[5],
	          EXT2_SB(fs)->s_uuid[6],
	          EXT2_SB(fs)->s_uuid[7],
	          EXT2_SB(fs)->s_uuid[8],
	          EXT2_SB(fs)->s_uuid[9],
	          EXT2_SB(fs)->s_uuid[10],
	          EXT2_SB(fs)->s_uuid[11],
	          EXT2_SB(fs)->s_uuid[12],
	          EXT2_SB(fs)->s_uuid[13],
	          EXT2_SB(fs)->s_uuid[14],
	          EXT2_SB(fs)->s_uuid[15]
	          ) < 0) {
	free(uuid);
	return NULL;
    }

    return uuid;
}

const struct fs_ops ext2_fs_ops = {
    .fs_name       = "ext2",
    .fs_flags      = FS_THISIND | FS_USEMEM,
    .fs_init       = ext2_fs_init,
    .searchdir     = NULL,
    .getfssec      = generic_getfssec,
    .close_file    = generic_close_file,
    .mangle_name   = generic_mangle_name,
    .chdir_start   = generic_chdir_start,
    .open_config   = generic_open_config,
    .iget_root     = ext2_iget_root,
    .iget          = ext2_iget,
    .readlink      = ext2_readlink,
    .readdir       = ext2_readdir,
    .next_extent   = ext2_next_extent,
    .fs_uuid       = ext2_fs_uuid,
};
