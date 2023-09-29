#ifndef _BTRFS_H_
#define _BTRFS_H_

#include <asm/types.h>
#include <linux/ioctl.h>

#define BTRFS_SUPER_MAGIC 0x9123683E
#define BTRFS_SUPER_INFO_OFFSET (64 * 1024)
#define BTRFS_SUPER_INFO_SIZE 4096
#define BTRFS_MAGIC "_BHRfS_M"
#define BTRFS_MAGIC_L 8
#define BTRFS_CSUM_SIZE 32
#define BTRFS_FSID_SIZE 16
#define BTRFS_UUID_SIZE 16

/* Fixed areas reserved for the boot loader */
#define BTRFS_BOOT_AREA_A_OFFSET	0
#define BTRFS_BOOT_AREA_A_SIZE		BTRFS_SUPER_INFO_OFFSET
#define BTRFS_BOOT_AREA_B_OFFSET	(256 * 1024)
#define BTRFS_BOOT_AREA_B_SIZE		((1024-256) * 1024)

typedef __u64 u64;
typedef __u32 u32;
typedef __u16 u16;
typedef __u8 u8;
typedef u64 __le64;
typedef u16 __le16;

#define BTRFS_ROOT_BACKREF_KEY  144
#define BTRFS_ROOT_TREE_DIR_OBJECTID 6ULL
#define BTRFS_DIR_ITEM_KEY      84

/*
 *  * this is used for both forward and backward root refs
 *   */
struct btrfs_root_ref {
        __le64 dirid;
        __le64 sequence;
        __le16 name_len;
} __attribute__ ((__packed__));

struct btrfs_disk_key {
        __le64 objectid;
        u8 type;
        __le64 offset;
} __attribute__ ((__packed__));

struct btrfs_dir_item {
        struct btrfs_disk_key location;
        __le64 transid;
        __le16 data_len;
        __le16 name_len;
        u8 type;
} __attribute__ ((__packed__));

struct btrfs_super_block {
        uint8_t csum[32];
        uint8_t fsid[16];
        uint64_t bytenr;
        uint64_t flags;
        uint8_t magic[8];
        uint64_t generation;
        uint64_t root;
        uint64_t chunk_root;
        uint64_t log_root;
        uint64_t log_root_transid;
        uint64_t total_bytes;
        uint64_t bytes_used;
        uint64_t root_dir_objectid;
        uint64_t num_devices;
        uint32_t sectorsize;
        uint32_t nodesize;
        uint32_t leafsize;
        uint32_t stripesize;
        uint32_t sys_chunk_array_size;
        uint64_t chunk_root_generation;
        uint64_t compat_flags;
        uint64_t compat_ro_flags;
        uint64_t incompat_flags;
        uint16_t csum_type;
        uint8_t root_level;
        uint8_t chunk_root_level;
        uint8_t log_root_level;
        struct btrfs_dev_item {
                uint64_t devid;
                uint64_t total_bytes;
                uint64_t bytes_used;
                uint32_t io_align;
                uint32_t io_width;
                uint32_t sector_size;
                uint64_t type;
                uint64_t generation;
                uint64_t start_offset;
                uint32_t dev_group;
                uint8_t seek_speed;
                uint8_t bandwidth;
                uint8_t uuid[16];
                uint8_t fsid[16];
        } __attribute__ ((__packed__)) dev_item;
        uint8_t label[256];
} __attribute__ ((__packed__));

#define BTRFS_IOCTL_MAGIC 0x94
#define BTRFS_VOL_NAME_MAX 255
#define BTRFS_PATH_NAME_MAX 4087

struct btrfs_ioctl_vol_args {
	__s64 fd;
	char name[BTRFS_PATH_NAME_MAX + 1];
};

struct btrfs_ioctl_search_key {
	/* which root are we searching.  0 is the tree of tree roots */
	__u64 tree_id;

	/* keys returned will be >= min and <= max */
	__u64 min_objectid;
	__u64 max_objectid;

	/* keys returned will be >= min and <= max */
	__u64 min_offset;
	__u64 max_offset;

	/* max and min transids to search for */
	__u64 min_transid;
	__u64 max_transid;

	/* keys returned will be >= min and <= max */
	__u32 min_type;
	__u32 max_type;

	/*
	 * how many items did userland ask for, and how many are we
	 * returning
	 */
	__u32 nr_items;

	/* align to 64 bits */
	__u32 unused;

	/* some extra for later */
	__u64 unused1;
	__u64 unused2;
	__u64 unused3;
	__u64 unused4;
};

struct btrfs_ioctl_search_header {
	__u64 transid;
	__u64 objectid;
	__u64 offset;
	__u32 type;
	__u32 len;
} __attribute__((may_alias));

#define BTRFS_DEVICE_PATH_NAME_MAX 1024
struct btrfs_ioctl_dev_info_args {
	__u64 devid;				/* in/out */
	__u8 uuid[BTRFS_UUID_SIZE];		/* in/out */
	__u64 bytes_used;			/* out */
	__u64 total_bytes;			/* out */
	__u64 unused[379];			/* pad to 4k */
	__u8 path[BTRFS_DEVICE_PATH_NAME_MAX];	/* out */
};

struct btrfs_ioctl_fs_info_args {
	__u64 max_id;				/* out */
	__u64 num_devices;			/* out */
	__u8 fsid[BTRFS_FSID_SIZE];		/* out */
	__u64 reserved[124];			/* pad to 1k */
};

#define BTRFS_SEARCH_ARGS_BUFSIZE (4096 - sizeof(struct btrfs_ioctl_search_key))
/*
 * the buf is an array of search headers where
 * each header is followed by the actual item
 * the type field is expanded to 32 bits for alignment
 */
struct btrfs_ioctl_search_args {
	struct btrfs_ioctl_search_key key;
	char buf[BTRFS_SEARCH_ARGS_BUFSIZE];
};

#define BTRFS_IOC_TREE_SEARCH _IOWR(BTRFS_IOCTL_MAGIC, 17, \
                                   struct btrfs_ioctl_search_args)
#define BTRFS_IOC_DEV_INFO _IOWR(BTRFS_IOCTL_MAGIC, 30, \
				 struct btrfs_ioctl_dev_info_args)
#define BTRFS_IOC_FS_INFO _IOR(BTRFS_IOCTL_MAGIC, 31, \
			       struct btrfs_ioctl_fs_info_args)

#endif
