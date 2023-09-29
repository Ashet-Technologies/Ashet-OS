/*
 * Copyright (C) 2011-2012 Paulo Alcantara <pcacjr@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the
 * Free Software Foundation, Inc.,
 * 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/

#include "runlist.h"

#ifndef _NTFS_H_
#define _NTFS_H_

struct ntfs_bpb {
    uint8_t jmp_boot[3];
    char oem_name[8];
    uint16_t sector_size;
    uint8_t sec_per_clust;
    uint16_t res_sectors;
    uint8_t zero_0[3];
    uint16_t zero_1;
    uint8_t media;
    uint16_t zero_2;
    uint16_t unused_0;
    uint16_t unused_1;
    uint32_t unused_2;
    uint32_t zero_3;
    uint32_t unused_3;
    uint64_t total_sectors;
    uint64_t mft_lclust;
    uint64_t mft_mirr_lclust;
    int8_t clust_per_mft_record;
    uint8_t unused_4[3];
    uint8_t clust_per_idx_record;
    uint8_t unused_5[3];
    uint64_t vol_serial;
    uint32_t unused_6;

    uint8_t pad[428];       /* padding to a sector boundary (512 bytes) */
} __attribute__((__packed__));

/* Function type for an NTFS-version-dependent MFT record lookup */
struct ntfs_mft_record;
typedef struct ntfs_mft_record *f_mft_record_lookup(struct fs_info *,
                                                    uint32_t, block_t *);

struct ntfs_sb_info {
    block_t mft_blk;                /* The first MFT record block */
    uint64_t mft_lcn;               /* LCN of the first MFT record */
    unsigned mft_size;              /* The MFT size in sectors */
    uint64_t mft_record_size;       /* MFT record size in bytes */

    uint8_t clust_per_idx_record;   /* Clusters per Index Record */

    unsigned long long clusters;    /* Total number of clusters */

    unsigned clust_shift;           /* Based on sectors */
    unsigned clust_byte_shift;      /* Based on bytes */
    unsigned clust_mask;
    unsigned clust_size;

    uint8_t major_ver;              /* Major version from $Volume */
    uint8_t minor_ver;              /* Minor version from $Volume */

    /* NTFS-version-dependent MFT record lookup function to use */
    f_mft_record_lookup *mft_record_lookup;
} __attribute__((__packed__));

/* The NTFS in-memory inode structure */
struct ntfs_inode {
    int64_t initialized_size;
    int64_t allocated_size;
    unsigned long mft_no;       /* Number of the mft record / inode */
    uint16_t seq_no;            /* Sequence number of the mft record */
    uint32_t type;              /* Attribute type of this inode */
    uint8_t non_resident;
    union {                 /* Non-resident $DATA attribute */
        struct {            /* Used only if non_resident flags isn't set */
            uint32_t offset;    /* Data offset */
        } resident;
        struct {            /* Used only if non_resident is set */
            struct runlist *rlist;
        } non_resident;
    } data;
    uint32_t start_cluster; /* Starting cluster address */
    sector_t start;         /* Starting sector */
    sector_t offset;        /* Current sector offset */
    sector_t here;          /* Sector corresponding to offset */
};

/* This is structure is used to keep a state for ntfs_readdir() callers.
 * As NTFS stores directory entries in a complex way, this is structure
 * ends up saving a state required to find out where we must start from
 * for the next ntfs_readdir() call.
 */
struct ntfs_readdir_state {
    unsigned long mft_no;       /* MFT record number */
    bool in_idx_root;           /* It's true if we're still in the INDEX root */
    uint32_t idx_blks_count;    /* Number of read INDX blocks */
    uint32_t entries_count;     /* Number of read INDEX entries */
    int64_t last_vcn;           /* Last VCN of the INDX block */
};

enum {
    MAP_UNSPEC,
    MAP_START           = 1 << 0,
    MAP_END             = 1 << 1,
    MAP_ALLOCATED       = 1 << 2,
    MAP_UNALLOCATED     = 1 << 3,
    MAP_MASK            = 0x0000000F,
};

struct mapping_chunk {
    uint64_t vcn;
    int64_t lcn;
    uint64_t len;
    uint32_t flags;
};

/* System defined attributes (32-bit)
 * Each attribute type has a corresponding attribute name (in Unicode)
 */
enum {
    NTFS_AT_UNUSED                      = 0x00,
    NTFS_AT_STANDARD_INFORMATION        = 0x10,
    NTFS_AT_ATTR_LIST                   = 0x20,
    NTFS_AT_FILENAME                    = 0x30,
    NTFS_AT_OBJ_ID                      = 0x40,
    NTFS_AT_SECURITY_DESCP              = 0x50,
    NTFS_AT_VOL_NAME                    = 0x60,
    NTFS_AT_VOL_INFO                    = 0x70,
    NTFS_AT_DATA                        = 0x80,
    NTFS_AT_INDEX_ROOT                  = 0x90,
    NTFS_AT_INDEX_ALLOCATION            = 0xA0,
    NTFS_AT_BITMAP                      = 0xB0,
    NTFS_AT_REPARSE_POINT               = 0xC0,
    NTFS_AT_EA_INFO                     = 0xD0,
    NTFS_AT_EA                          = 0xE0,
    NTFS_AT_PROPERTY_SET                = 0xF0,
    NTFS_AT_LOGGED_UTIL_STREAM          = 0x100,
    NTFS_AT_FIRST_USER_DEFINED_ATTR     = 0x1000,
    NTFS_AT_END                         = 0xFFFFFFFF,
};

/* NTFS File Permissions (also called attributes in DOS terminology) */
enum {
    NTFS_FILE_ATTR_READONLY                     = 0x00000001,
    NTFS_FILE_ATTR_HIDDEN                       = 0x00000002,
    NTFS_FILE_ATTR_SYSTEM                       = 0x00000004,
    NTFS_FILE_ATTR_DIRECTORY                    = 0x00000010,
    NTFS_FILE_ATTR_ARCHIVE                      = 0x00000020,
    NTFS_FILE_ATTR_DEVICE                       = 0x00000040,
    NTFS_FILE_ATTR_NORMAL                       = 0x00000080,
    NTFS_FILE_ATTR_TEMPORARY                    = 0x00000100,
    NTFS_FILE_ATTR_SPARSE_FILE                  = 0x00000200,
    NTFS_FILE_ATTR_REPARSE_POINT                = 0x00000400,
    NTFS_FILE_ATTR_COMPRESSED                   = 0x00000800,
    NTFS_FILE_ATTR_OFFLINE                      = 0x00001000,
    NTFS_FILE_ATTR_NOT_CONTENT_INDEXED          = 0x00002000,
    NTFS_FILE_ATTR_ENCRYPTED                    = 0x00004000,
    NTFS_FILE_ATTR_VALID_FLAGS                  = 0x00007FB7,
    NTFS_FILE_ATTR_VALID_SET_FLAGS              = 0x000031A7,
    NTFS_FILE_ATTR_DUP_FILE_NAME_INDEX_PRESENT  = 0x10000000,
    NTFS_FILE_ATTR_DUP_VIEW_INDEX_PRESENT       = 0x20000000,
};

/*
 * Magic identifiers present at the beginning of all ntfs record containing
 * records (like mft records for example).
 */
enum {
    /* Found in $MFT/$DATA */
    NTFS_MAGIC_FILE     = 0x454C4946,   /* MFT entry */
    NTFS_MAGIC_INDX     = 0x58444E49,   /* Index buffer */
    NTFS_MAGIC_HOLE     = 0x454C4F48,

    /* Found in $LogFile/$DATA */
    NTFS_MAGIC_RSTR     = 0x52545352,
    NTFS_MAGIC_RCRD     = 0x44524352,
    /* Found in $LogFile/$DATA (May be found in $MFT/$DATA, also ?) */
    NTFS_MAGIC_CHKDSK   = 0x444B4843,
    /* Found in all ntfs record containing records. */
    NTFS_MAGIC_BAAD     = 0x44414142,
    NTFS_MAGIC_EMPTY    = 0xFFFFFFFF,   /* Record is empty */
};

struct ntfs_record {
    uint32_t magic;
    uint16_t usa_ofs;
    uint16_t usa_count;
} __attribute__((__packed__)) NTFS_RECORD;

/* The $MFT metadata file types */
enum ntfs_system_file {
    FILE_MFT            = 0,
    FILE_MFTMirr        = 1,
    FILE_LogFile        = 2,
    FILE_Volume         = 3,
    FILE_AttrDef        = 4,
    FILE_root           = 5,
    FILE_Bitmap         = 6,
    FILE_Boot           = 7,
    FILE_BadClus        = 8,
    FILE_Secure         = 9,
    FILE_UpCase         = 10,
    FILE_Extend         = 11,
    FILE_reserved12     = 12,
    FILE_reserved13     = 13,
    FILE_reserved14     = 14,
    FILE_reserved15     = 15,
    FILE_reserved16     = 16,
};

enum {
    MFT_RECORD_IN_USE       = 0x0001,
    MFT_RECORD_IS_DIRECTORY = 0x0002,
} __attribute__((__packed__));

struct ntfs_mft_record {
    uint32_t magic;
    uint16_t usa_ofs;
    uint16_t usa_count;
    uint64_t lsn;
    uint16_t seq_no;
    uint16_t link_count;
    uint16_t attrs_offset;
    uint16_t flags;     /* MFT record flags */
    uint32_t bytes_in_use;
    uint32_t bytes_allocated;
    uint64_t base_mft_record;
    uint16_t next_attr_instance;
    uint16_t reserved;
    uint32_t mft_record_no;
} __attribute__((__packed__));   /* 48 bytes */

/* This is the version without the NTFS 3.1+ specific fields */
struct ntfs_mft_record_old {
    uint32_t magic;
    uint16_t usa_ofs;
    uint16_t usa_count;
    uint64_t lsn;
    uint16_t seq_no;
    uint16_t link_count;
    uint16_t attrs_offset;
    uint16_t flags;     /* MFT record flags */
    uint32_t bytes_in_use;
    uint32_t bytes_allocated;
    uint64_t base_mft_record;
    uint16_t next_attr_instance;
} __attribute__((__packed__));   /* 42 bytes */

enum {
    ATTR_DEF_INDEXABLE          = 0x02,
    ATTR_DEF_MULTIPLE           = 0x04,
    ATTR_DEF_NOT_ZERO           = 0x08,
    ATTR_DEF_INDEXED_UNIQUE     = 0x10,
    ATTR_DEF_NAMED_UNIQUE       = 0x20,
    ATTR_DEF_RESIDENT           = 0x40,
    ATTR_DEF_ALWAYS_LOG         = 0x80,
};

struct ntfs_attr_record {
    uint32_t type;      /* Attr. type code */
    uint32_t len;
    uint8_t non_resident;
    uint8_t name_len;
    uint16_t name_offset;
    uint16_t flags;     /* Attr. flags */
    uint16_t instance;
    union {
        struct {    /* Resident attribute */
            uint32_t value_len;
            uint16_t value_offset;
            uint8_t flags;  /* Flags of resident attributes */
            int8_t reserved;
        } __attribute__((__packed__)) resident;
        struct {    /* Non-resident attributes */
            uint64_t lowest_vcn;
            uint64_t highest_vcn;
            uint16_t mapping_pairs_offset;
            uint8_t compression_unit;
            uint8_t reserved[5];
            int64_t allocated_size;
            int64_t data_size; /* Byte size of the attribute value.
                                * Note: it can be larger than
                                * allocated_size if attribute value is
                                * compressed or sparse.
                                */
            int64_t initialized_size;
            int64_t compressed_size;
        } __attribute__((__packed__)) non_resident;
    } __attribute__((__packed__)) data;
} __attribute__((__packed__));

/* Attribute: Attribute List (0x20)
 * Note: it can be either resident or non-resident
 */
struct ntfs_attr_list_entry {
    uint32_t type;
    uint16_t length;
    uint8_t name_length;
    uint8_t name_offset;
    uint64_t lowest_vcn;
    uint64_t mft_ref;
    uint16_t instance;
    uint16_t name[0];
} __attribute__((__packed__));

#define NTFS_MAX_FILE_NAME_LEN 255

/* Possible namespaces for filenames in ntfs (8-bit) */
enum {
    FILE_NAME_POSIX             = 0x00,
    FILE_NAME_WIN32             = 0x01,
    FILE_NAME_DOS               = 0x02,
    FILE_NAME_WIN32_AND_DOS     = 0x03,
} __attribute__((__packed__));

/* Attribute: Filename (0x30)
 * Note: always resident
 */
struct ntfs_filename_attr {
    uint64_t parent_directory;
    int64_t ctime;
    int64_t atime;
    int64_t mtime;
    int64_t rtime;
    uint64_t allocated_size;
    uint64_t data_size;
    uint32_t file_attrs;
    union {
        struct {
            uint16_t packed_ea_size;
            uint16_t reserved;      /* reserved for alignment */
        } __attribute__((__packed__)) ea;
        struct {
            uint32_t reparse_point_tag;
        } __attribute__((__packed__)) rp;
    } __attribute__((__packed__)) type;
    uint8_t file_name_len;
    uint8_t file_name_type;
    uint16_t file_name[0];          /* File name in Unicode */
} __attribute__((__packed__));

/* Attribute: Volume Name (0x60)
 * Note: always resident
 * Note: Present only in FILE_volume
 */
struct ntfs_vol_name {
    uint16_t name[0];       /* The name of the volume in Unicode */
} __attribute__((__packed__));

/* Attribute: Volume Information (0x70)
 * Note: always resident
 * Note: present only in FILE_Volume
 */
struct ntfs_vol_info {
    uint64_t reserved;
    uint8_t major_ver;
    uint8_t minor_ver;
    uint16_t flags;     /* Volume flags */
} __attribute__((__packed__));

/* Attribute: Data attribute (0x80)
 * Note: can be either resident or non-resident
 */
struct ntfs_data_attr {
    uint8_t data[0];
} __attribute__((__packed__));

/* Index header flags (8-bit) */
enum {
    SMALL_INDEX = 0,
    LARGE_INDEX = 1,
    LEAF_NODE   = 0,
    INDEX_NODE  = 1,
    NODE_MASK   = 1,
} __attribute__((__packed__));

/* Header for the indexes, describing the INDEX_ENTRY records, which
 * follow the struct ntfs_idx_header.
 */
struct ntfs_idx_header {
    uint32_t entries_offset;
    uint32_t index_len;
    uint32_t allocated_size;
    uint8_t flags;              /* Index header flags */
    uint8_t reserved[3];        /* Align to 8-byte boundary */
} __attribute__((__packed__));

/* Attribute: Index Root (0x90)
 * Note: always resident
 */
struct ntfs_idx_root {
    uint32_t type;  /* It is $FILE_NAME for directories, zero for view indexes.
                     * No other values allowed.
                     */
    uint32_t collation_rule;
    uint32_t index_block_size;
    uint8_t clust_per_index_block;
    uint8_t reserved[3];
    struct ntfs_idx_header index;
} __attribute__((__packed__));

/* Attribute: Index allocation (0xA0)
 * Note: always non-resident, of course! :-)
 */
struct ntfs_idx_allocation {
    uint32_t magic;
    uint16_t usa_ofs;           /* Update Sequence Array offsets */
    uint16_t usa_count;         /* Update Sequence Array number in bytes */
    int64_t lsn;
    int64_t index_block_vcn;    /* Virtual cluster number of the index block */
    struct ntfs_idx_header index;
} __attribute__((__packed__));

enum {
    INDEX_ENTRY_NODE            = 1,
    INDEX_ENTRY_END             = 2,
    /* force enum bit width to 16-bit */
    INDEX_ENTRY_SPACE_FILTER    = 0xFFFF,
} __attribute__((__packed__));

struct ntfs_idx_entry_header {
    union {
        struct { /* Only valid when INDEX_ENTRY_END is not set */
            uint64_t indexed_file;
        } __attribute__((__packed__)) dir;
        struct { /* Used for views/indexes to find the entry's data */
            uint16_t data_offset;
            uint16_t data_len;
            uint32_t reservedV;
        } __attribute__((__packed__)) vi;
    } __attribute__((__packed__)) data;
    uint16_t len;
    uint16_t key_len;
    uint16_t flags;     /* Index entry flags */
    uint16_t reserved;  /* Align to 8-byte boundary */
} __attribute__((__packed__));

struct ntfs_idx_entry {
    union {
        struct { /* Only valid when INDEX_ENTRY_END is not set */
            uint64_t indexed_file;
        } __attribute__((__packed__)) dir;
        struct { /* Used for views/indexes to find the entry's data */
            uint16_t data_offset;
            uint16_t data_len;
            uint32_t reservedV;
        } __attribute__((__packed__)) vi;
    } __attribute__((__packed__)) data;
    uint16_t len;
    uint16_t key_len;
    uint16_t flags;     /* Index entry flags */
    uint16_t reserved;  /* Align to 8-byte boundary */
    union {
        struct ntfs_filename_attr file_name;
        //SII_INDEX_KEY sii;
        //SDH_INDEX_KEY sdh;
        //GUID object_id;
        //REPARSE_INDEX_KEY reparse;
        //SID sid;
        uint32_t owner_id;
    } __attribute__((__packed__)) key;
} __attribute__((__packed__));

static inline struct ntfs_sb_info *NTFS_SB(struct fs_info *fs)
{
    return fs->fs_info;
}

#define NTFS_PVT(i) ((struct ntfs_inode *)((i)->pvt))

#endif /* _NTFS_H_ */
