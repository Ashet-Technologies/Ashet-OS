#ifndef ISO9660_FS_H
#define ISO9660_FS_H

#include <klibc/compiler.h>
#include <stdint.h>

/* Boot info table */
struct iso_boot_info {
    uint32_t pvd;		/* LBA of primary volume descriptor */
    uint32_t file;		/* LBA of boot file */
    uint32_t length;		/* Length of boot file */
    uint32_t csum;		/* Checksum of boot file */
    uint32_t reserved[10];	/* Currently unused */
};

extern struct iso_boot_info iso_boot_info; /* In isolinux.asm */

/* The root dir entry offset in the primary volume descriptor */
#define ROOT_DIR_OFFSET   156

struct iso_dir_entry {
    uint8_t length;                         /* 00 */
    uint8_t ext_attr_length;                /* 01 */    
    uint32_t extent_le;			    /* 02 */
    uint32_t extent_be;			    /* 06 */
    uint32_t size_le;			    /* 0a */  
    uint32_t size_be;			    /* 0e */
    uint8_t date[7];                        /* 12 */
    uint8_t flags;                          /* 19 */
    uint8_t file_unit_size;                 /* 1a */
    uint8_t interleave;                     /* 1b */
    uint16_t volume_sequence_number_le;	    /* 1c */
    uint16_t volume_sequence_number_be;	    /* 1e */
    uint8_t name_len;                       /* 20 */
    char    name[0];                        /* 21 */
} __packed;

struct iso_sb_info {
    struct iso_dir_entry root;

    int do_rr;       /* 1 , 2 = try to process Rock Ridge info , 0 = do not.
                        2 indicates that the id of RRIP 1.12 was found.
                     */
    int susp_skip;   /* Skip length from SUSP entry SP */
};

/*
 * iso9660 private inode information
 */
struct iso9660_pvt_inode {
    uint32_t lba;		/* Starting LBA of file data area*/
};

#define PVT(i) ((struct iso9660_pvt_inode *)((i)->pvt))

#endif /* iso9660_fs.h */
