/*
 * btrfs.c -- readonly btrfs support for syslinux
 * Some data structures are derivated from btrfs-tools-0.19 ctree.h
 * Copyright 2009-2014 Intel Corporation; authors: Alek Du, H. Peter Anvin
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 * Boston MA 02111-1307, USA; either version 2 of the License, or
 * (at your option) any later version; incorporated herein by reference.
 *
 */

#include <dprintf.h>
#include <stdio.h>
#include <string.h>
#include <cache.h>
#include <core.h>
#include <disk.h>
#include <fs.h>
#include <dirent.h>
#include <minmax.h>
#include "btrfs.h"

union tree_buf {
	struct btrfs_header header;
	struct btrfs_node node;
	struct btrfs_leaf leaf;
};

/* filesystem instance structure */
struct btrfs_info {
	u64 fs_tree;
	struct btrfs_super_block sb;
	struct btrfs_chunk_map chunk_map;
	union tree_buf *tree_buf;
};

/* compare function used for bin_search */
typedef int (*cmp_func)(const void *ptr1, const void *ptr2);

/* simple but useful bin search, used for chunk search and btree search */
static int bin_search(void *ptr, int item_size, void *cmp_item, cmp_func func,
		      int min, int max, int *slot)
{
	int low = min;
	int high = max;
	int mid;
	int ret;
	unsigned long offset;
	void *item;

	while (low < high) {
		mid = (low + high) / 2;
		offset = mid * item_size;

		item = ptr + offset;
		ret = func(item, cmp_item);

		if (ret < 0)
			low = mid + 1;
		else if (ret > 0)
			high = mid;
		else {
			*slot = mid;
			return 0;
		}
	}
	*slot = low;
	return 1;
}

static int btrfs_comp_chunk_map(struct btrfs_chunk_map_item *m1,
				struct btrfs_chunk_map_item *m2)
{
	if (m1->logical > m2->logical)
		return 1;
	if (m1->logical < m2->logical)
		return -1;
	return 0;
}

/* insert a new chunk mapping item */
static void insert_map(struct fs_info *fs, struct btrfs_chunk_map_item *item)
{
	struct btrfs_info * const bfs = fs->fs_info;
	struct btrfs_chunk_map *chunk_map = &bfs->chunk_map;
	int ret;
	int slot;
	int i;

	if (chunk_map->map == NULL) { /* first item */
		chunk_map->map_length = BTRFS_MAX_CHUNK_ENTRIES;
		chunk_map->map = malloc(chunk_map->map_length
					* sizeof(chunk_map->map[0]));
		chunk_map->map[0] = *item;
		chunk_map->cur_length = 1;
		return;
	}
	ret = bin_search(chunk_map->map, sizeof(*item), item,
			(cmp_func)btrfs_comp_chunk_map, 0,
			chunk_map->cur_length, &slot);
	if (ret == 0)/* already in map */
		return;
	if (chunk_map->cur_length == BTRFS_MAX_CHUNK_ENTRIES) {
		/* should be impossible */
		printf("too many chunk items\n");
		return;
	}
	for (i = chunk_map->cur_length; i > slot; i--)
		chunk_map->map[i] = chunk_map->map[i-1];
	chunk_map->map[slot] = *item;
	chunk_map->cur_length++;
}

/*
 * from sys_chunk_array or chunk_tree, we can convert a logical address to
 * a physical address we can not support multi device case yet
 */
static u64 logical_physical(struct fs_info *fs, u64 logical)
{
	struct btrfs_info * const bfs = fs->fs_info;
	struct btrfs_chunk_map *chunk_map = &bfs->chunk_map;
	struct btrfs_chunk_map_item item;
	int slot, ret;

	item.logical = logical;
	ret = bin_search(chunk_map->map, sizeof(chunk_map->map[0]), &item,
			(cmp_func)btrfs_comp_chunk_map, 0,
			chunk_map->cur_length, &slot);
	if (ret == 0)
		slot++;
	else if (slot == 0)
		return -1;
	if (logical >=
		chunk_map->map[slot-1].logical + chunk_map->map[slot-1].length)
		return -1;
	return chunk_map->map[slot-1].physical + logical -
			chunk_map->map[slot-1].logical;
}

/* btrfs has several super block mirrors, need to calculate their location */
static inline u64 btrfs_sb_offset(int mirror)
{
	u64 start = 16 * 1024;
	if (mirror)
		return start << (BTRFS_SUPER_MIRROR_SHIFT * mirror);
	return BTRFS_SUPER_INFO_OFFSET;
}

/* find the most recent super block */
static void btrfs_read_super_block(struct fs_info *fs)
{
	int i;
	int ret;
	u8 fsid[BTRFS_FSID_SIZE];
	u64 offset;
	u64 transid = 0;
	struct btrfs_super_block buf;
	struct btrfs_info * const bfs = fs->fs_info;

	bfs->sb.total_bytes = ~0; /* Unknown as of yet */

	/* find most recent super block */
	for (i = 0; i < BTRFS_SUPER_MIRROR_MAX; i++) {
		offset = btrfs_sb_offset(i);
		if (offset >= bfs->sb.total_bytes)
			break;

		ret = cache_read(fs, (char *)&buf, offset, sizeof(buf));
		if (ret < sizeof(buf))
			break;

		if (buf.bytenr != offset ||
		    strncmp((char *)(&buf.magic), BTRFS_MAGIC,
			    sizeof(buf.magic)))
			continue;

		if (i == 0)
			memcpy(fsid, buf.fsid, sizeof(fsid));
		else if (memcmp(fsid, buf.fsid, sizeof(fsid)))
			continue;

		if (buf.generation > transid) {
			memcpy(&bfs->sb, &buf, sizeof(bfs->sb));
			transid = buf.generation;
		}
	}
}

static inline unsigned long btrfs_chunk_item_size(int num_stripes)
{
	return sizeof(struct btrfs_chunk) +
		sizeof(struct btrfs_stripe) * (num_stripes - 1);
}

static void clear_path(struct btrfs_path *path)
{
	memset(path, 0, sizeof(*path));
}

static int btrfs_comp_keys(const struct btrfs_disk_key *k1,
			   const struct btrfs_disk_key *k2)
{
	if (k1->objectid > k2->objectid)
		return 1;
	if (k1->objectid < k2->objectid)
		return -1;
	if (k1->type > k2->type)
		return 1;
	if (k1->type < k2->type)
		return -1;
	if (k1->offset > k2->offset)
		return 1;
	if (k1->offset < k2->offset)
		return -1;
	return 0;
}

/* compare keys but ignore offset, is useful to enumerate all same kind keys */
static int btrfs_comp_keys_type(const struct btrfs_disk_key *k1,
				const struct btrfs_disk_key *k2)
{
	if (k1->objectid > k2->objectid)
		return 1;
	if (k1->objectid < k2->objectid)
		return -1;
	if (k1->type > k2->type)
		return 1;
	if (k1->type < k2->type)
		return -1;
	return 0;
}

/* seach tree directly on disk ... */
static int search_tree(struct fs_info *fs, u64 loffset,
		       struct btrfs_disk_key *key, struct btrfs_path *path)
{
	struct btrfs_info * const bfs = fs->fs_info;
	union tree_buf *tree_buf = bfs->tree_buf;
	int slot, ret;
	u64 offset;

	offset = logical_physical(fs, loffset);
	cache_read(fs, &tree_buf->header, offset, sizeof(tree_buf->header));
	if (tree_buf->header.level) {
		/* inner node */
		cache_read(fs, (char *)&tree_buf->node.ptrs[0],
			   offset + sizeof tree_buf->header,
			   bfs->sb.nodesize - sizeof tree_buf->header);
		path->itemsnr[tree_buf->header.level] = tree_buf->header.nritems;
		path->offsets[tree_buf->header.level] = loffset;
		ret = bin_search(&tree_buf->node.ptrs[0],
				 sizeof(struct btrfs_key_ptr),
				 key, (cmp_func)btrfs_comp_keys,
				 path->slots[tree_buf->header.level],
				 tree_buf->header.nritems, &slot);
		if (ret && slot > path->slots[tree_buf->header.level])
			slot--;
		path->slots[tree_buf->header.level] = slot;
		ret = search_tree(fs, tree_buf->node.ptrs[slot].blockptr,
				  key, path);
	} else {
		/* leaf node */
		cache_read(fs, (char *)&tree_buf->leaf.items[0],
			   offset + sizeof tree_buf->header,
			   bfs->sb.leafsize - sizeof tree_buf->header);
		path->itemsnr[tree_buf->header.level] = tree_buf->header.nritems;
		path->offsets[tree_buf->header.level] = loffset;
		ret = bin_search(&tree_buf->leaf.items[0],
				 sizeof(struct btrfs_item),
				 key, (cmp_func)btrfs_comp_keys,
				 path->slots[0],
				 tree_buf->header.nritems, &slot);
		if (ret && slot > path->slots[tree_buf->header.level])
			slot--;
		path->slots[tree_buf->header.level] = slot;
		path->item = tree_buf->leaf.items[slot];
		cache_read(fs, (char *)&path->data,
			   offset + sizeof tree_buf->header +
			   tree_buf->leaf.items[slot].offset,
			   tree_buf->leaf.items[slot].size);
	}
	return ret;
}

/* return 0 if leaf found */
static int next_leaf(struct fs_info *fs, struct btrfs_disk_key *key, struct btrfs_path *path)
{
	int slot;
	int level = 1;

	while (level < BTRFS_MAX_LEVEL) {
		if (!path->itemsnr[level]) /* no more nodes */
			return 1;
		slot = path->slots[level] + 1;
		if (slot >= path->itemsnr[level]) {
			level++;
			continue;;
		}
		path->slots[level] = slot;
		path->slots[level-1] = 0; /* reset low level slots info */
		search_tree(fs, path->offsets[level], key, path);
		break;
	}
	if (level == BTRFS_MAX_LEVEL)
		return 1;
	return 0;
}

/* return 0 if slot found */
static int next_slot(struct fs_info *fs, struct btrfs_disk_key *key,
		     struct btrfs_path *path)
{
	int slot;

	if (!path->itemsnr[0])
		return 1;
	slot = path->slots[0] + 1;
	if (slot >= path->itemsnr[0])
		return 1;
	path->slots[0] = slot;
	search_tree(fs, path->offsets[0], key, path);
	return 0;
}

/*
 * read chunk_array in super block
 */
static void btrfs_read_sys_chunk_array(struct fs_info *fs)
{
	struct btrfs_info * const bfs = fs->fs_info;
	struct btrfs_chunk_map_item item;
	struct btrfs_disk_key *key;
	struct btrfs_chunk *chunk;
	int cur;

	/* read chunk array in superblock */
	cur = 0;
	while (cur < bfs->sb.sys_chunk_array_size) {
		key = (struct btrfs_disk_key *)(bfs->sb.sys_chunk_array + cur);
		cur += sizeof(*key);
		chunk = (struct btrfs_chunk *)(bfs->sb.sys_chunk_array + cur);
		cur += btrfs_chunk_item_size(chunk->num_stripes);
		/* insert to mapping table, ignore multi stripes */
		item.logical = key->offset;
		item.length = chunk->length;
		item.devid = chunk->stripe.devid;
		item.physical = chunk->stripe.offset;/*ignore other stripes */
		insert_map(fs, &item);
	}
}

/* read chunk items from chunk_tree and insert them to chunk map */
static void btrfs_read_chunk_tree(struct fs_info *fs)
{
	struct btrfs_info * const bfs = fs->fs_info;
	struct btrfs_disk_key search_key;
	struct btrfs_chunk *chunk;
	struct btrfs_chunk_map_item item;
	struct btrfs_path path;

	if (!(bfs->sb.flags & BTRFS_SUPER_FLAG_METADUMP)) {
		if (bfs->sb.num_devices > 1)
			printf("warning: only support single device btrfs\n");
		/* read chunk from chunk_tree */
		search_key.objectid = BTRFS_FIRST_CHUNK_TREE_OBJECTID;
		search_key.type = BTRFS_CHUNK_ITEM_KEY;
		search_key.offset = 0;
		clear_path(&path);
		search_tree(fs, bfs->sb.chunk_root, &search_key, &path);
		do {
			do {
				if (btrfs_comp_keys_type(&search_key,
							&path.item.key))
					break;
				chunk = (struct btrfs_chunk *)(path.data);
				/* insert to mapping table, ignore stripes */
				item.logical = path.item.key.offset;
				item.length = chunk->length;
				item.devid = chunk->stripe.devid;
				item.physical = chunk->stripe.offset;
				insert_map(fs, &item);
			} while (!next_slot(fs, &search_key, &path));
			if (btrfs_comp_keys_type(&search_key, &path.item.key))
				break;
		} while (!next_leaf(fs, &search_key, &path));
	}
}

static inline u64 btrfs_name_hash(const char *name, int len)
{
	return btrfs_crc32c((u32)~1, name, len);
}

static struct inode *btrfs_iget_by_inr(struct fs_info *fs, u64 inr)
{
	struct btrfs_info * const bfs = fs->fs_info;
	struct inode *inode;
	struct btrfs_inode_item inode_item;
	struct btrfs_disk_key search_key;
	struct btrfs_path path;
	int ret;

	/* FIXME: some BTRFS inode member are u64, while our logical inode
           is u32, we may need change them to u64 later */
	search_key.objectid = inr;
	search_key.type = BTRFS_INODE_ITEM_KEY;
	search_key.offset = 0;
	clear_path(&path);
	ret = search_tree(fs, bfs->fs_tree, &search_key, &path);
	if (ret)
		return NULL;
	inode_item = *(struct btrfs_inode_item *)path.data;
	if (!(inode = alloc_inode(fs, inr, sizeof(struct btrfs_pvt_inode))))
		return NULL;
	inode->ino = inr;
	inode->size = inode_item.size;
	inode->mode = IFTODT(inode_item.mode);

	if (inode->mode == DT_REG || inode->mode == DT_LNK) {
		struct btrfs_file_extent_item extent_item;
		u64 offset;

		/* get file_extent_item */
		search_key.type = BTRFS_EXTENT_DATA_KEY;
		search_key.offset = 0;
		clear_path(&path);
		ret = search_tree(fs, bfs->fs_tree, &search_key, &path);
		if (ret)
			return NULL; /* impossible */
		extent_item = *(struct btrfs_file_extent_item *)path.data;
		if (extent_item.type == BTRFS_FILE_EXTENT_INLINE)/* inline file */
			offset = path.offsets[0] + sizeof(struct btrfs_header)
				+ path.item.offset
				+ offsetof(struct btrfs_file_extent_item, disk_bytenr);
		else
			offset = extent_item.disk_bytenr;
		PVT(inode)->offset = offset;
	}
	return inode;
}

static struct inode *btrfs_iget_root(struct fs_info *fs)
{
	/* BTRFS_FIRST_CHUNK_TREE_OBJECTID(256) actually is first OBJECTID for FS_TREE */
	return btrfs_iget_by_inr(fs, BTRFS_FIRST_CHUNK_TREE_OBJECTID);
}

static struct inode *btrfs_iget(const char *name, struct inode *parent)
{
	struct fs_info * const fs = parent->fs;
	struct btrfs_info * const bfs = fs->fs_info;
	struct btrfs_disk_key search_key;
	struct btrfs_path path;
	struct btrfs_dir_item dir_item;
	int ret;

	search_key.objectid = parent->ino;
	search_key.type = BTRFS_DIR_ITEM_KEY;
	search_key.offset = btrfs_name_hash(name, strlen(name));
	clear_path(&path);
	ret = search_tree(fs, bfs->fs_tree, &search_key, &path);
	if (ret)
		return NULL;
	dir_item = *(struct btrfs_dir_item *)path.data;

	return btrfs_iget_by_inr(fs, dir_item.location.objectid);
}

static int btrfs_readlink(struct inode *inode, char *buf)
{
	cache_read(inode->fs, buf,
		   logical_physical(inode->fs, PVT(inode)->offset),
		   inode->size);
	buf[inode->size] = '\0';
	return inode->size;
}

static int btrfs_readdir(struct file *file, struct dirent *dirent)
{
	struct fs_info * const fs = file->fs;
	struct btrfs_info * const bfs = fs->fs_info;
	struct inode * const inode = file->inode;
	struct btrfs_disk_key search_key;
	struct btrfs_path path;
	struct btrfs_dir_item *dir_item;
	int ret;

	/*
	 * we use file->offset to store last search key.offset, will will search
	 * key that lower that offset, 0 means first search and we will search
         * -1UL, which is the biggest possible key
         */
	search_key.objectid = inode->ino;
	search_key.type = BTRFS_DIR_ITEM_KEY;
	search_key.offset = file->offset - 1;
	clear_path(&path);
	ret = search_tree(fs, bfs->fs_tree, &search_key, &path);

	if (ret) {
		if (btrfs_comp_keys_type(&search_key, &path.item.key))
			return -1;
	}

	dir_item = (struct btrfs_dir_item *)path.data;
	file->offset = path.item.key.offset;
	dirent->d_ino = dir_item->location.objectid;
	dirent->d_off = file->offset;
	dirent->d_reclen = offsetof(struct dirent, d_name)
		+ dir_item->name_len + 1;
	dirent->d_type = IFTODT(dir_item->type);
	memcpy(dirent->d_name, dir_item + 1, dir_item->name_len);
	dirent->d_name[dir_item->name_len] = '\0';

	return 0;
}

static int btrfs_next_extent(struct inode *inode, uint32_t lstart)
{
	struct btrfs_disk_key search_key;
	struct btrfs_file_extent_item extent_item;
	struct btrfs_path path;
	int ret;
	u64 offset;
	struct fs_info * const fs = inode->fs;
	struct btrfs_info * const bfs = fs->fs_info;
	u32 sec_shift = SECTOR_SHIFT(fs);
	u32 sec_size = SECTOR_SIZE(fs);

	search_key.objectid = inode->ino;
	search_key.type = BTRFS_EXTENT_DATA_KEY;
	search_key.offset = lstart << sec_shift;
	clear_path(&path);
	ret = search_tree(fs, bfs->fs_tree, &search_key, &path);
	if (ret) { /* impossible */
		printf("btrfs: search extent data error!\n");
		return -1;
	}
	extent_item = *(struct btrfs_file_extent_item *)path.data;

	if (extent_item.encryption) {
	    printf("btrfs: found encrypted data, cannot continue!\n");
	    return -1;
	}
	if (extent_item.compression) {
	    printf("btrfs: found compressed data, cannot continue!\n");
	    return -1;
	}

	if (extent_item.type == BTRFS_FILE_EXTENT_INLINE) {/* inline file */
		/* we fake a extent here, and PVT of inode will tell us */
		offset = path.offsets[0] + sizeof(struct btrfs_header)
			+ path.item.offset
			+ offsetof(struct btrfs_file_extent_item, disk_bytenr);
		inode->next_extent.len =
			(inode->size + sec_size -1) >> sec_shift;
	} else {
		offset = extent_item.disk_bytenr + extent_item.offset;
		inode->next_extent.len =
			(extent_item.num_bytes + sec_size - 1) >> sec_shift;
	}
	inode->next_extent.pstart = logical_physical(fs, offset) >> sec_shift;
	PVT(inode)->offset = offset;
	return 0;
}

static uint32_t btrfs_getfssec(struct file *file, char *buf, int sectors,
					bool *have_more)
{
	u32 ret;
	struct fs_info *fs = file->fs;
	u32 off = PVT(file->inode)->offset % SECTOR_SIZE(fs);
	bool handle_inline = false;

	if (off && !file->offset) {/* inline file first read patch */
		file->inode->size += off;
		handle_inline = true;
	}
	ret = generic_getfssec(file, buf, sectors, have_more);
	if (!ret)
		return ret;
	off = PVT(file->inode)->offset % SECTOR_SIZE(fs);
	if (handle_inline) {/* inline file patch */
		ret -= off;
		memcpy(buf, buf + off, ret);
	}
	return ret;
}

static void btrfs_get_fs_tree(struct fs_info *fs)
{
	struct btrfs_info * const bfs = fs->fs_info;
	struct btrfs_disk_key search_key;
	struct btrfs_path path;
	struct btrfs_root_item *tree;
	bool subvol_ok = false;

	/* check if subvol is filled by installer */
	if (*SubvolName) {
		search_key.objectid = BTRFS_FS_TREE_OBJECTID;
		search_key.type = BTRFS_ROOT_REF_KEY;
		search_key.offset = 0;
		clear_path(&path);
		if (search_tree(fs, bfs->sb.root, &search_key, &path))
			next_slot(fs, &search_key, &path);
		do {
			do {
				struct btrfs_root_ref *ref;
				int pathlen;

				if (btrfs_comp_keys_type(&search_key,
							&path.item.key))
					break;
				ref = (struct btrfs_root_ref *)path.data;
				pathlen = path.item.size - sizeof(struct btrfs_root_ref);

				if (!strncmp((char*)(ref + 1), SubvolName, pathlen)) {
					subvol_ok = true;
					break;
				}
			} while (!next_slot(fs, &search_key, &path));
			if (subvol_ok)
				break;
			if (btrfs_comp_keys_type(&search_key, &path.item.key))
				break;
		} while (!next_leaf(fs, &search_key, &path));
		if (!subvol_ok) /* should be impossible */
			printf("no subvol found!\n");
	}
	/* find fs_tree from tree_root */
	if (subvol_ok)
		search_key.objectid = path.item.key.offset;
	else /* "default" volume */
		search_key.objectid = BTRFS_FS_TREE_OBJECTID;
	search_key.type = BTRFS_ROOT_ITEM_KEY;
	search_key.offset = -1;
	clear_path(&path);
	search_tree(fs, bfs->sb.root, &search_key, &path);
	tree = (struct btrfs_root_item *)path.data;
	bfs->fs_tree = tree->bytenr;
}

/* init. the fs meta data, return the block size shift bits. */
static int btrfs_fs_init(struct fs_info *fs)
{
	struct disk *disk = fs->fs_dev->disk;
	struct btrfs_info *bfs;

	btrfs_init_crc32c();
    
	bfs = zalloc(sizeof(struct btrfs_info));
	if (!bfs)
		return -1;

	fs->fs_info = bfs;

	fs->sector_shift = disk->sector_shift;
	fs->sector_size  = 1 << fs->sector_shift;
	fs->block_shift  = BTRFS_BLOCK_SHIFT;
	fs->block_size   = 1 << fs->block_shift;

	/* Initialize the block cache */
	cache_init(fs->fs_dev, fs->block_shift);

	btrfs_read_super_block(fs);
	if (bfs->sb.magic != BTRFS_MAGIC_N)
		return -1;
	bfs->tree_buf = malloc(max(bfs->sb.nodesize, bfs->sb.leafsize));
	if (!bfs->tree_buf)
		return -1;
	btrfs_read_sys_chunk_array(fs);
	btrfs_read_chunk_tree(fs);
	btrfs_get_fs_tree(fs);

	return fs->block_shift;
}

const struct fs_ops btrfs_fs_ops = {
    .fs_name       = "btrfs",
    .fs_flags      = 0,
    .fs_init       = btrfs_fs_init,
    .iget_root     = btrfs_iget_root,
    .iget          = btrfs_iget,
    .readlink      = btrfs_readlink,
    .getfssec      = btrfs_getfssec,
    .close_file    = generic_close_file,
    .mangle_name   = generic_mangle_name,
    .next_extent   = btrfs_next_extent,
    .readdir       = btrfs_readdir,
    .chdir_start   = generic_chdir_start,
    .open_config   = generic_open_config,
    .fs_uuid       = NULL,
};
