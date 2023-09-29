#ifndef _BTRFS_H_
#define _BTRFS_H_

#include <stdint.h>
#include <zconf.h>

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
/* type that store on disk, but it is same as cpu type for i386 arch */
typedef u16 __le16;
typedef u32 __le32;
typedef u64 __le64;

#include "crc32c.h"
#define btrfs_crc32c crc32c_le

#define BTRFS_SUPER_INFO_OFFSET (64 * 1024)
#define BTRFS_SUPER_INFO_SIZE 4096
#define BTRFS_MAX_LEAF_SIZE 4096
#define BTRFS_BLOCK_SHIFT 12
#define BTRFS_BLOCK_SIZE  (1 << BTRFS_BLOCK_SHIFT)

#define BTRFS_SUPER_MIRROR_MAX   3
#define BTRFS_SUPER_MIRROR_SHIFT 12
#define BTRFS_CSUM_SIZE 32
#define BTRFS_FSID_SIZE 16
#define BTRFS_LABEL_SIZE 256
#define BTRFS_SYSTEM_CHUNK_ARRAY_SIZE 2048
#define BTRFS_UUID_SIZE 16

#define BTRFS_MAGIC "_BHRfS_M"
#define BTRFS_MAGIC_L 8
#define BTRFS_MAGIC_N 0x4d5f53665248425f

#define BTRFS_SUPER_FLAG_METADUMP	(1ULL << 33)

#define BTRFS_DEV_ITEM_KEY	216
#define BTRFS_CHUNK_ITEM_KEY	228
#define BTRFS_ROOT_REF_KEY	156
#define BTRFS_ROOT_ITEM_KEY	132
#define BTRFS_EXTENT_DATA_KEY	108
#define BTRFS_DIR_ITEM_KEY	84
#define BTRFS_INODE_ITEM_KEY	1

#define BTRFS_EXTENT_TREE_OBJECTID 2ULL
#define BTRFS_FS_TREE_OBJECTID 5ULL

#define BTRFS_FIRST_CHUNK_TREE_OBJECTID 256ULL

#define BTRFS_FILE_EXTENT_INLINE 0
#define BTRFS_FILE_EXTENT_REG 1
#define BTRFS_FILE_EXTENT_PREALLOC 2

#define BTRFS_MAX_LEVEL 8
#define BTRFS_MAX_CHUNK_ENTRIES 256

#define BTRFS_FT_REG_FILE	1
#define BTRFS_FT_DIR		2
#define BTRFS_FT_SYMLINK	7

#define ROOT_DIR_WORD 0x002f

struct btrfs_dev_item {
	__le64 devid;
	__le64 total_bytes;
	__le64 bytes_used;
	__le32 io_align;
	__le32 io_width;
	__le32 sector_size;
	__le64 type;
	__le64 generation;
	__le64 start_offset;
	__le32 dev_group;
	u8 seek_speed;
	u8 bandwidth;
	u8 uuid[BTRFS_UUID_SIZE];
	u8 fsid[BTRFS_UUID_SIZE];
} __attribute__ ((__packed__));

struct btrfs_super_block {
	u8 csum[BTRFS_CSUM_SIZE];
	/* the first 3 fields must match struct btrfs_header */
	u8 fsid[BTRFS_FSID_SIZE];    /* FS specific uuid */
	__le64 bytenr; /* this block number */
	__le64 flags;

	/* allowed to be different from the btrfs_header from here own down */
	__le64 magic;
	__le64 generation;
	__le64 root;
	__le64 chunk_root;
	__le64 log_root;

	/* this will help find the new super based on the log root */
	__le64 log_root_transid;
	__le64 total_bytes;
	__le64 bytes_used;
	__le64 root_dir_objectid;
	__le64 num_devices;
	__le32 sectorsize;
	__le32 nodesize;
	__le32 leafsize;
	__le32 stripesize;
	__le32 sys_chunk_array_size;
	__le64 chunk_root_generation;
	__le64 compat_flags;
	__le64 compat_ro_flags;
	__le64 incompat_flags;
	__le16 csum_type;
	u8 root_level;
	u8 chunk_root_level;
	u8 log_root_level;
	struct btrfs_dev_item dev_item;

	char label[BTRFS_LABEL_SIZE];

	/* future expansion */
	__le64 reserved[32];
	u8 sys_chunk_array[BTRFS_SYSTEM_CHUNK_ARRAY_SIZE];
} __attribute__ ((__packed__));

struct btrfs_disk_key {
	__le64 objectid;
	u8 type;
	__le64 offset;
} __attribute__ ((__packed__));

struct btrfs_stripe {
	__le64 devid;
	__le64 offset;
	u8 dev_uuid[BTRFS_UUID_SIZE];
} __attribute__ ((__packed__));

struct btrfs_chunk {
	__le64 length;
	__le64 owner;
	__le64 stripe_len;
	__le64 type;
	__le32 io_align;
	__le32 io_width;
	__le32 sector_size;
	__le16 num_stripes;
	__le16 sub_stripes;
	struct btrfs_stripe stripe;
} __attribute__ ((__packed__));

struct btrfs_header {
	/* these first four must match the super block */
	u8 csum[BTRFS_CSUM_SIZE];
	u8 fsid[BTRFS_FSID_SIZE]; /* FS specific uuid */
	__le64 bytenr; /* which block this node is supposed to live in */
	__le64 flags;

	/* allowed to be different from the super from here on down */
	u8 chunk_tree_uuid[BTRFS_UUID_SIZE];
	__le64 generation;
	__le64 owner;
	__le32 nritems;
	u8 level;
} __attribute__ ((__packed__));

struct btrfs_item {
	struct btrfs_disk_key key;
	__le32 offset;
	__le32 size;
} __attribute__ ((__packed__));

struct btrfs_leaf {
	struct btrfs_header header;
	struct btrfs_item items[];
} __attribute__ ((__packed__));

struct btrfs_key_ptr {
	struct btrfs_disk_key key;
	__le64 blockptr;
	__le64 generation;
} __attribute__ ((__packed__));

struct btrfs_node {
	struct btrfs_header header;
	struct btrfs_key_ptr ptrs[];
} __attribute__ ((__packed__));

/* remember how we get to a node/leaf */
struct btrfs_path {
	u64 offsets[BTRFS_MAX_LEVEL];
	int itemsnr[BTRFS_MAX_LEVEL];
	int slots[BTRFS_MAX_LEVEL];
	/* remember last slot's item and data */
	struct btrfs_item item;
	u8 data[BTRFS_MAX_LEAF_SIZE];
};

/* store logical offset to physical offset mapping */
struct btrfs_chunk_map_item {
	u64 logical;
	u64 length;
	u64 devid;
	u64 physical;
};

struct btrfs_chunk_map {
	struct btrfs_chunk_map_item *map;
	u32 map_length;
	u32 cur_length;
};

struct btrfs_timespec {
	__le64 sec;
	__le32 nsec;
} __attribute__ ((__packed__));

struct btrfs_inode_item {
	/* nfs style generation number */
	__le64 generation;
	/* transid that last touched this inode */
	__le64 transid;
	__le64 size;
	__le64 nbytes;
	__le64 block_group;
	__le32 nlink;
	__le32 uid;
	__le32 gid;
	__le32 mode;
	__le64 rdev;
	__le64 flags;

	/* modification sequence number for NFS */
	__le64 sequence;

	/*
	 * a little future expansion, for more than this we can
	 * just grow the inode item and version it
	 */
	__le64 reserved[4];
	struct btrfs_timespec atime;
	struct btrfs_timespec ctime;
	struct btrfs_timespec mtime;
	struct btrfs_timespec otime;
} __attribute__ ((__packed__));

struct btrfs_root_item {
	struct btrfs_inode_item inode;
	__le64 generation;
	__le64 root_dirid;
	__le64 bytenr;
	__le64 byte_limit;
	__le64 bytes_used;
	__le64 last_snapshot;
	__le64 flags;
	__le32 refs;
	struct btrfs_disk_key drop_progress;
	u8 drop_level;
	u8 level;
} __attribute__ ((__packed__));

struct btrfs_dir_item {
	struct btrfs_disk_key location;
	__le64 transid;
	__le16 data_len;
	__le16 name_len;
	u8 type;
} __attribute__ ((__packed__));

struct btrfs_file_extent_item {
	__le64 generation;
	__le64 ram_bytes;
	u8 compression;
	u8 encryption;
	__le16 other_encoding; /* spare for later use */
	u8 type;
	__le64 disk_bytenr;
	__le64 disk_num_bytes;
	__le64 offset;
	__le64 num_bytes;
} __attribute__ ((__packed__));

struct btrfs_root_ref {
	__le64 dirid;
	__le64 sequence;
	__le16 name_len;
} __attribute__ ((__packed__));

/*
 * btrfs private inode information
 */
struct btrfs_pvt_inode {
    uint64_t offset;
};

#define PVT(i) ((struct btrfs_pvt_inode *)((i)->pvt))

#endif
