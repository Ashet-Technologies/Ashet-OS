#ifndef FAT_FS_H
#define FAT_FS_H

#include <stdint.h>

#define FAT_DIR_ENTRY_SIZE 32
#define DIRENT_SHIFT 5

#define FAT_ATTR_READ_ONLY 0x01
#define FAT_ATTR_HIDDEN	   0x02
#define FAT_ATTR_SYSTEM	   0x04
#define FAT_ATTR_VOLUME_ID 0x08
#define FAT_ATTR_DIRECTORY 0x10
#define FAT_ATTR_ARCHIVE   0x20

#define FAT_MAXFILE	   256

#define FAT_ATTR_LONG_NAME (FAT_ATTR_READ_ONLY             \
                            | FAT_ATTR_HIDDEN              \
                            | FAT_ATTR_SYSTEM              \
                            | FAT_ATTR_VOLUME_ID)

#define FAT_ATTR_VALID	   (FAT_ATTR_READ_ONLY             \
                            | FAT_ATTR_HIDDEN              \
                            | FAT_ATTR_SYSTEM              \
                            | FAT_ATTR_DIRECTORY           \
                            | FAT_ATTR_ARCHIVE)

enum fat_type{ FAT12, FAT16, FAT32 };

/*
 * The fat file system structures 
 */

struct fat_bpb {
        uint8_t  jmp_boot[3];
        uint8_t  oem_name[8];
        uint16_t sector_size;
        uint8_t  bxSecPerClust;
        uint16_t bxResSectors;
        uint8_t  bxFATs;
        uint16_t bxRootDirEnts;
        uint16_t bxSectors;
        uint8_t  media;
        uint16_t bxFATsecs;
        uint16_t sectors_per_track;
        uint16_t num_heads;
        uint32_t num_hidden_sectors;
        uint32_t bsHugeSectors;
       
        union {
                struct {
                        uint8_t  num_ph_drive;
                        uint8_t  reserved;
                        uint8_t  boot_sig;
                        uint32_t num_serial;
                        uint8_t  label[11];
                        uint8_t  fstype[8];
                } __attribute__ ((packed)) fat12_16;

                struct {
                        uint32_t bxFATsecs_32;
                        uint16_t extended_flags;
                        uint16_t fs_version;
                        uint32_t root_cluster;
                        uint16_t fs_info;
                        uint16_t backup_boot_sector;
                        uint8_t  reserved[12];
                        uint8_t  num_ph_drive;
                        uint8_t  reserved1;
                        uint8_t  boot_sig;
                        uint32_t num_serial;
                        uint8_t  label[11];
                        uint8_t  fstype[8];
                } __attribute__ ((packed)) fat32;

        } __attribute__ ((packed));

        uint8_t pad[422];  /* padding to 512 Bytes (one sector) */

} __attribute__ ((packed));

/*
 * The fat file system info in memory 
 */
struct fat_sb_info {
	sector_t fat;             /* The FAT region */
	sector_t root;            /* The root dir region */
	sector_t data;            /* The data region */

	uint32_t clusters;	  /* Total number of clusters */
	uint32_t root_cluster;	  /* Cluster number for (FAT32) root dir */
	int      root_size;       /* The root dir size in sectors */
	
	int      clust_shift;      /* based on sectors */
	int      clust_byte_shift; /* based on bytes   */
	int      clust_mask;	   /* sectors per cluster mask */
	int      clust_size;

	int      fat_type;

	uint32_t uuid;             /* fs UUID */
} __attribute__ ((packed));

struct fat_dir_entry {
        char     name[11];
        uint8_t  attr;
        uint8_t  lcase;
        uint8_t  c_time_tenth;
        uint16_t c_time;
        uint16_t c_date;
        uint16_t a_date;
        uint16_t first_cluster_high;
        uint16_t w_time;
        uint16_t w_date;
        uint16_t first_cluster_low;
        uint32_t file_size;
} __attribute__ ((packed));

#define LCASE_BASE 8       /* basename is lower case */
#define LCASE_EXT  16      /* extension is lower case */

struct fat_long_name_entry {
        uint8_t  id;
        uint16_t name1[5];
        uint8_t  attr;
        uint8_t  reserved;
        uint8_t  checksum;
        uint16_t name2[6];
        uint16_t first_cluster;
        uint16_t name3[2];
} __attribute__ ((packed));

static inline struct fat_sb_info *FAT_SB(struct fs_info *fs)
{
        return fs->fs_info;
}

/* 
 * Count the root dir size in sectors
 */
static inline int root_dir_size(struct fs_info *fs, struct fat_bpb *fat)
{
    return (fat->bxRootDirEnts + SECTOR_SIZE(fs)/32 - 1)
	>> (SECTOR_SHIFT(fs) - 5);
}

/*
 * FAT private inode information
 */
struct fat_pvt_inode {
    uint32_t start_cluster;	/* Starting cluster address */
    sector_t start;		/* Starting sector */
    sector_t offset;		/* Current sector offset */
    sector_t here;		/* Sector corresponding to offset */
};

#define PVT(i) ((struct fat_pvt_inode *)((i)->pvt))

#endif /* fat_fs.h */
