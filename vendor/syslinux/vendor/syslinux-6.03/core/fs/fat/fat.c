#include <dprintf.h>
#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <sys/dirent.h>
#include <cache.h>
#include <core.h>
#include <disk.h>
#include <fs.h>
#include <ilog2.h>
#include <klibc/compiler.h>
#include "codepage.h"
#include "fat_fs.h"

static struct inode * new_fat_inode(struct fs_info *fs)
{
    struct inode *inode = alloc_inode(fs, 0, sizeof(struct fat_pvt_inode));
    if (!inode)
	malloc_error("inode structure");

    return inode;
}

/*
 * Check for a particular sector in the FAT cache
 */
static const void *get_fat_sector(struct fs_info *fs, sector_t sector)
{
    return get_cache(fs->fs_dev, FAT_SB(fs)->fat + sector);
}

static uint32_t get_next_cluster(struct fs_info *fs, uint32_t clust_num)
{
    uint32_t next_cluster = 0;
    sector_t fat_sector;
    uint32_t offset;
    uint32_t sector_mask = SECTOR_SIZE(fs) - 1;
    const uint8_t *data;

    switch(FAT_SB(fs)->fat_type) {
    case FAT12:
	offset = clust_num + (clust_num >> 1);
	fat_sector = offset >> SECTOR_SHIFT(fs);
	offset &= sector_mask;
	data = get_fat_sector(fs, fat_sector);
	if (offset == sector_mask) {
	    /*
	     * we got the end of the one fat sector,
	     * but we have just one byte and we need two,
	     * so store the low part, then read the next fat
	     * sector, read the high part, then combine it.
	     */
	    next_cluster = data[offset];
	    data = get_fat_sector(fs, fat_sector + 1);
	    next_cluster += data[0] << 8;
	} else {
	    next_cluster = *(const uint16_t *)(data + offset);
	}

	if (clust_num & 0x0001)
	    next_cluster >>= 4;         /* cluster number is ODD */
	else
	    next_cluster &= 0x0fff;     /* cluster number is EVEN */
	break;

    case FAT16:
	offset = clust_num << 1;
	fat_sector = offset >> SECTOR_SHIFT(fs);
	offset &= sector_mask;
	data = get_fat_sector(fs, fat_sector);
	next_cluster = *(const uint16_t *)(data + offset);
	break;

    case FAT32:
	offset = clust_num << 2;
	fat_sector = offset >> SECTOR_SHIFT(fs);
	offset &= sector_mask;
	data = get_fat_sector(fs, fat_sector);
	next_cluster = *(const uint32_t *)(data + offset);
	next_cluster &= 0x0fffffff;
	break;
    }

    return next_cluster;
}

static int fat_next_extent(struct inode *inode, uint32_t lstart)
{
    struct fs_info *fs = inode->fs;
    struct fat_sb_info *sbi = FAT_SB(fs);
    uint32_t mcluster = lstart >> sbi->clust_shift;
    uint32_t lcluster;
    uint32_t pcluster;
    uint32_t tcluster;
    uint32_t xcluster;
    const uint32_t cluster_bytes = UINT32_C(1) << sbi->clust_byte_shift;
    const uint32_t cluster_secs  = UINT32_C(1) << sbi->clust_shift;
    sector_t data_area = sbi->data;

    tcluster = (inode->size + cluster_bytes - 1) >> sbi->clust_byte_shift;
    if (mcluster >= tcluster)
	goto err;		/* Requested cluster beyond end of file */

    lcluster = PVT(inode)->offset >> sbi->clust_shift;
    pcluster = ((PVT(inode)->here - data_area) >> sbi->clust_shift) + 2;

    if (lcluster > mcluster || PVT(inode)->here < data_area) {
	lcluster = 0;
	pcluster = PVT(inode)->start_cluster;
    }

    for (;;) {
	if (pcluster-2 >= sbi->clusters) {
	    inode->size = lcluster << sbi->clust_shift;
	    goto err;
	}

	if (lcluster >= mcluster)
	    break;

	lcluster++;
	pcluster = get_next_cluster(fs, pcluster);
    }

    inode->next_extent.pstart =
	((sector_t)(pcluster-2) << sbi->clust_shift) + data_area;
    inode->next_extent.len = cluster_secs;
    xcluster = 0;		/* Nonsense */

    while (++lcluster < tcluster) {
	xcluster = get_next_cluster(fs, pcluster);
	if (xcluster != ++pcluster)
	    break;		/* Not contiguous */
	inode->next_extent.len += cluster_secs;
    }

    /* Note: ->here is bogus if ->offset >= EOF, but that's okay */
    PVT(inode)->offset = lcluster << sbi->clust_shift;
    PVT(inode)->here   = ((xcluster-2) << sbi->clust_shift) + data_area;

    return 0;

err:
    dprintf("fat_next_extent: return error\n");
    return -1;
}

static sector_t get_next_sector(struct fs_info* fs, uint32_t sector)
{
    struct fat_sb_info *sbi = FAT_SB(fs);
    sector_t data_area = sbi->data;
    sector_t data_sector;
    uint32_t cluster;
    int clust_shift = sbi->clust_shift;

    if (sector < data_area) {
	/* Root directory sector... */
	sector++;
	if (sector >= data_area)
	    sector = 0; /* Ran out of root directory, return EOF */
	return sector;
    }

    data_sector = sector - data_area;
    if ((data_sector + 1) & sbi->clust_mask)  /* Still in the same cluster */
	return sector + 1;		      /* Next sector inside cluster */

    /* get a new cluster */
    cluster = data_sector >> clust_shift;
    cluster = get_next_cluster(fs, cluster + 2) - 2;

    if (cluster >= sbi->clusters)
	return 0;

    /* return the start of the new cluster */
    sector = (cluster << clust_shift) + data_area;
    return sector;
}

/*
 * The FAT is a single-linked list.  We remember the last place we
 * were, so for a forward seek we can move forward from there, but
 * for a reverse seek we have to start over...
 */
static sector_t get_the_right_sector(struct file *file)
{
    struct inode *inode = file->inode;
    uint32_t sector_pos  = file->offset >> SECTOR_SHIFT(file->fs);
    uint32_t where;
    sector_t sector;

    if (sector_pos < PVT(inode)->offset) {
	/* Reverse seek */
	where = 0;
	sector = PVT(inode)->start;
    } else {
	where = PVT(inode)->offset;
	sector = PVT(inode)->here;
    }

    while (where < sector_pos) {
	sector = get_next_sector(file->fs, sector);
	where++;
    }

    PVT(inode)->offset = sector_pos;
    PVT(inode)->here   = sector;

    return sector;
}

/*
 * Get the next sector in sequence
 */
static sector_t next_sector(struct file *file)
{
    struct inode *inode = file->inode;
    sector_t sector = get_next_sector(file->fs, PVT(inode)->here);
    PVT(inode)->offset++;
    PVT(inode)->here = sector;

    return sector;
}

/**
 * mangle_name:
 *
 * Mangle a filename pointed to by src into a buffer pointed
 * to by dst; ends on encountering any whitespace.
 * dst is preserved.
 *
 * This verifies that a filename is < FILENAME_MAX characters,
 * doesn't contain whitespace, zero-pads the output buffer,
 * and removes redundant slashes.
 *
 * Unlike the generic version, this also converts backslashes to
 * forward slashes.
 *
 */
static void vfat_mangle_name(char *dst, const char *src)
{
    char *p = dst;
    int i = FILENAME_MAX-1;
    char c;

    while (not_whitespace(c = *src)) {
	if (c == '\\')
	    c = '/';

        if (c == '/') {
            if (src[1] == '/' || src[1] == '\\') {
                src++;
                i--;
                continue;
            }
        }
        i--;
        *dst++ = *src++;
    }

    while (1) {
        if (dst == p)
            break;
        if (dst[-1] != '/')
            break;
	if ((dst[-1] == '/') && ((dst - 1) == p))
	    break;

        dst--;
        i++;
    }

    i++;
    for (; i > 0; i --)
        *dst++ = '\0';
}

/*
 * Mangle a normal style string to DOS style string.
 */
static void mangle_dos_name(char *mangle_buf, const char *src)
{
    int i;
    unsigned char c;

    if (src[0] == '.' && (!src[1] || (src[1] == '.' && !src[2]))) {
	/* . and .. mangle to their respective zero-padded version */
	i = stpcpy(mangle_buf, src) - mangle_buf;
    } else {
	i = 0;
	while (i < 11) {
	    c = *src++;
	    
	if ((c <= ' ') || (c == '/'))
	    break;
	
	if (c == '.') {
	    while (i < 8)
		mangle_buf[i++] = ' ';
	    i = 8;
	    continue;
	}
	
	c = codepage.upper[c];
	if (i == 0 && c == 0xe5)
	    c = 0x05;		/* Special hack for the first byte only! */
	
	mangle_buf[i++] = c;
	}
    }

    while (i < 11)
	mangle_buf[i++] = ' ';

    mangle_buf[i] = '\0';
}

/*
 * Match a string name against a longname.  "len" is the number of
 * codepoints in the input; including padding.
 *
 * Returns true on match.
 */
static bool vfat_match_longname(const char *str, const uint16_t *match,
				int len)
{
    unsigned char c = -1;	/* Nonzero: we have not yet seen NUL */
    uint16_t cp;

    dprintf("Matching: %s len %d\n", str, len);

    while (len) {
	cp = *match++;
	len--;
	if (!cp)
	    break;
	c = *str++;
	if (cp != codepage.uni[0][c] && cp != codepage.uni[1][c])
	    return false;	/* Also handles c == '\0' */
    }

    /* This should have been the end of the matching string */
    if (*str)
	return false;

    /* Any padding entries must be FFFF */
    while (len--)
	if (*match++ != 0xffff)
	    return false;

    return true;
}

/*
 * Convert an UTF-16 longname to the system codepage; return
 * the length on success or -1 on failure.
 */
static int vfat_cvt_longname(char *entry_name, const uint16_t *long_name)
{
    struct unicache {
	uint16_t utf16;
	uint8_t cp;
    };
    static struct unicache unicache[256];
    struct unicache *uc;
    uint16_t cp;
    unsigned int c;
    char *p = entry_name;

    do {
	cp = *long_name++;
	uc = &unicache[cp % 256];

	if (__likely(uc->utf16 == cp)) {
	    *p++ = uc->cp;
	} else {
	    for (c = 0; c < 512; c++) {
		/* This is a bit hacky... */
		if (codepage.uni[0][c] == cp) {
		    uc->utf16 = cp;
		    *p++ = uc->cp = (uint8_t)c;
		    goto found;
		}
	    }
	    return -1;		/* Impossible character */
	found:
	    ;
	}
    } while (cp);

    return (p-entry_name)-1;
}

static void copy_long_chunk(uint16_t *buf, const struct fat_dir_entry *de)
{
    const struct fat_long_name_entry *le =
	(const struct fat_long_name_entry *)de;

    memcpy(buf,      le->name1, 5 * 2);
    memcpy(buf + 5,  le->name2, 6 * 2);
    memcpy(buf + 11, le->name3, 2 * 2);
}

static uint8_t get_checksum(const char *dir_name)
{
    int  i;
    uint8_t sum = 0;

    for (i = 11; i; i--)
	sum = ((sum & 1) << 7) + (sum >> 1) + (uint8_t)*dir_name++;
    return sum;
}


/* compute the first sector number of one dir where the data stores */
static inline sector_t first_sector(struct fs_info *fs,
				    const struct fat_dir_entry *dir)
{
    const struct fat_sb_info *sbi = FAT_SB(fs);
    sector_t first_clust;
    sector_t sector;

    first_clust = (dir->first_cluster_high << 16) + dir->first_cluster_low;
    if (first_clust == 0)
	sector = sbi->root;	/* first_clust == 0 means root directory */
    else
	sector = ((first_clust - 2) << sbi->clust_shift) + sbi->data;

    return sector;
}

static inline enum dirent_type get_inode_mode(uint8_t attr)
{
    return (attr & FAT_ATTR_DIRECTORY) ? DT_DIR : DT_REG;
}


static struct inode *vfat_find_entry(const char *dname, struct inode *dir)
{
    struct fs_info *fs = dir->fs;
    struct inode *inode;
    const struct fat_dir_entry *de;
    struct fat_long_name_entry *long_de;

    char mangled_name[12];
    uint16_t long_name[260];	/* == 20*13 */
    int long_len;

    sector_t dir_sector = PVT(dir)->start;
    uint8_t vfat_init, vfat_next, vfat_csum = 0;
    uint8_t id;
    int slots;
    int entries;
    int checksum;
    int long_match = 0;

    slots = (strlen(dname) + 12) / 13;
    if (slots > 20)
	return NULL;		/* Name too long */

    slots |= 0x40;
    vfat_init = vfat_next = slots;
    long_len = slots*13;

    /* Produce the shortname version, in case we need it. */
    mangle_dos_name(mangled_name, dname);

    while (dir_sector) {
	de = get_cache(fs->fs_dev, dir_sector);
	entries = 1 << (fs->sector_shift - 5);

	while (entries--) {
	    if (de->name[0] == 0)
		return NULL;

	    if (de->attr == 0x0f) {
		/*
		 * It's a long name entry.
		 */
		long_de = (struct fat_long_name_entry *)de;
		id = long_de->id;
		if (id != vfat_next)
		    goto not_match;

		if (id & 0x40) {
		    /* get the initial checksum value */
		    vfat_csum = long_de->checksum;
		    id &= 0x3f;
		    long_len = id * 13;

		    /* ZERO the long_name buffer */
		    memset(long_name, 0, sizeof long_name);
		} else {
		    if (long_de->checksum != vfat_csum)
			goto not_match;
		}

		vfat_next = --id;

		/* got the long entry name */
		copy_long_chunk(long_name + id*13, de);

		/*
		 * If we got the last entry, check it.
		 * Or, go on with the next entry.
		 */
		if (id == 0) {
		    if (!vfat_match_longname(dname, long_name, long_len))
			goto not_match;
		    long_match = 1;
		}
		de++;
		continue;     /* Try the next entry */
	    } else {
		/*
		 * It's a short entry
		 */
		if (de->attr & 0x08) /* ignore volume labels */
		    goto not_match;

		if (long_match) {
		    /*
		     * We already have a VFAT long name match. However, the
		     * match is only valid if the checksum matches.
		     */
		    checksum = get_checksum(de->name);
		    if (checksum == vfat_csum)
			goto found;  /* Got it */
		} else {
		    if (!memcmp(mangled_name, de->name, 11))
			goto found;
		}
	    }

	not_match:
	    vfat_next = vfat_init;
	    long_match = 0;

	    de++;
	}

	/* Try with the next sector */
	dir_sector = get_next_sector(fs, dir_sector);
    }
    return NULL;		/* Nothing found... */

found:
    inode = new_fat_inode(fs);
    inode->size = de->file_size;
    PVT(inode)->start_cluster = 
	(de->first_cluster_high << 16) + de->first_cluster_low;
    if (PVT(inode)->start_cluster == 0) {
	/* Root directory */
	int root_size = FAT_SB(fs)->root_size;

	PVT(inode)->start_cluster = FAT_SB(fs)->root_cluster;
	inode->size = root_size ? root_size << fs->sector_shift : ~0;
	PVT(inode)->start = PVT(inode)->here = FAT_SB(fs)->root;
    } else {
	PVT(inode)->start = PVT(inode)->here = first_sector(fs, de);
    }
    inode->mode = get_inode_mode(de->attr);

    return inode;
}

static struct inode *vfat_iget_root(struct fs_info *fs)
{
    struct inode *inode = new_fat_inode(fs);
    int root_size = FAT_SB(fs)->root_size;

    /*
     * For FAT32, the only way to get the root directory size is to
     * follow the entire FAT chain to the end... which seems pointless.
     */
    PVT(inode)->start_cluster = FAT_SB(fs)->root_cluster;
    inode->size = root_size ? root_size << fs->sector_shift : ~0;
    PVT(inode)->start = PVT(inode)->here = FAT_SB(fs)->root;
    inode->mode = DT_DIR;

    return inode;
}

static struct inode *vfat_iget(const char *dname, struct inode *parent)
{
    return vfat_find_entry(dname, parent);
}

static int vfat_readdir(struct file *file, struct dirent *dirent)
{
    struct fs_info *fs = file->fs;
    const struct fat_dir_entry *de;
    const char *data;
    const struct fat_long_name_entry *long_de;

    sector_t sector = get_the_right_sector(file);

    uint16_t long_name[261];	/* == 20*13 + 1 (to guarantee null) */
    char filename[261];
    int name_len = 0;

    uint8_t vfat_next, vfat_csum;
    uint8_t id;
    int entries_left;
    bool long_entry = false;
    int sec_off = file->offset & ((1 << fs->sector_shift) - 1);

    data = get_cache(fs->fs_dev, sector);
    de = (const struct fat_dir_entry *)(data + sec_off);
    entries_left = ((1 << fs->sector_shift) - sec_off) >> 5;

    vfat_next = vfat_csum = 0xff;

    while (1) {
	while (entries_left--) {
	    if (de->name[0] == 0)
		return -1;	/* End of directory */
	    if ((uint8_t)de->name[0] == 0xe5)
		goto invalid;

	    if (de->attr == 0x0f) {
		/*
		 * It's a long name entry.
		 */
		long_de = (struct fat_long_name_entry *)de;
		id = long_de->id;

		if (id & 0x40) {
		    /* init vfat_csum */
		    vfat_csum = long_de->checksum;
		    id &= 0x3f;
		    if (id >= 20)
			goto invalid; /* Too long! */

		    /* ZERO the long_name buffer */
		    memset(long_name, 0, sizeof long_name);
		} else {
		    if (long_de->checksum != vfat_csum || id != vfat_next)
			goto invalid;
		}

		vfat_next = --id;

		/* got the long entry name */
		copy_long_chunk(long_name + id*13, de);

		if (id == 0) {
		    name_len = vfat_cvt_longname(filename, long_name);
		    if (name_len > 0 && name_len < sizeof(dirent->d_name))
			long_entry = true;
		}

		goto next;
	    } else {
		/*
		 * It's a short entry
		 */
		if (de->attr & 0x08) /* ignore volume labels */
		    goto invalid;

		if (long_entry && get_checksum(de->name) == vfat_csum) {
		   /* Got a long entry */
		} else {
		    /* Use the shortname */
		    int i;
		    uint8_t c;
		    char *p = filename;

		    for (i = 0; i < 8; i++) {
			c = de->name[i];
			if (c == ' ')
			    break;
			if (de->lcase & LCASE_BASE)
			    c = codepage.lower[c];
			*p++ = c;
		    }
		    if (de->name[8] != ' ') {
			*p++ = '.';
			for (i = 8; i < 11; i++) {
			    c = de->name[i];
			    if (c == ' ')
				break;
			    if (de->lcase & LCASE_EXT)
				c = codepage.lower[c];
			    *p++ = c;
			}
		    }
		    *p = '\0';
		    name_len = p - filename;
		}
		goto got;	/* Got something one way or the other */
	    }

	invalid:
	    long_entry = false;
	next:
	    de++;
	    file->offset += sizeof(struct fat_dir_entry);
	}

	/* Try with the next sector */
	sector = next_sector(file);
	if (!sector)
	    return -1;
	de = get_cache(fs->fs_dev, sector);
	entries_left = 1 << (fs->sector_shift - 5);
    }

got:
    name_len++;			/* Include final null */
    dirent->d_ino = de->first_cluster_low | (de->first_cluster_high << 16);
    dirent->d_off = file->offset;
    dirent->d_reclen = offsetof(struct dirent, d_name) + name_len;
    dirent->d_type = get_inode_mode(de->attr);
    memcpy(dirent->d_name, filename, name_len);

    file->offset += sizeof(*de);  /* Update for next reading */

    return 0;
}

/* init. the fs meta data, return the block size in bits */
static int vfat_fs_init(struct fs_info *fs)
{
    struct fat_bpb fat;
    struct fat_sb_info *sbi;
    struct disk *disk = fs->fs_dev->disk;
    int sectors_per_fat;
    uint32_t clusters;
    sector_t total_sectors;

    fs->sector_shift = fs->block_shift = disk->sector_shift;
    fs->sector_size  = 1 << fs->sector_shift;
    fs->block_size   = 1 << fs->block_shift;

    disk->rdwr_sectors(disk, &fat, 0, 1, 0);

    /* XXX: Find better sanity checks... */
    if (!fat.bxResSectors || !fat.bxFATs)
	return -1;
    sbi = malloc(sizeof(*sbi));
    if (!sbi)
	malloc_error("fat_sb_info structure");
    fs->fs_info = sbi;

    sectors_per_fat = fat.bxFATsecs ? : fat.fat32.bxFATsecs_32;
    total_sectors   = fat.bxSectors ? : fat.bsHugeSectors;

    sbi->fat       = fat.bxResSectors;
    sbi->root      = sbi->fat + sectors_per_fat * fat.bxFATs;
    sbi->root_size = root_dir_size(fs, &fat);
    sbi->data      = sbi->root + sbi->root_size;

    sbi->clust_shift      = ilog2(fat.bxSecPerClust);
    sbi->clust_byte_shift = sbi->clust_shift + fs->sector_shift;
    sbi->clust_mask       = fat.bxSecPerClust - 1;
    sbi->clust_size       = fat.bxSecPerClust << fs->sector_shift;

    clusters = (total_sectors - sbi->data) >> sbi->clust_shift;
    if (clusters <= 0xff4) {
	sbi->fat_type = FAT12;
    } else if (clusters <= 0xfff4) {
	sbi->fat_type = FAT16;
    } else {
	sbi->fat_type = FAT32;

	if (clusters > 0x0ffffff4)
	    clusters = 0x0ffffff4; /* Maximum possible */

	if (fat.fat32.extended_flags & 0x80) {
	    /* Non-mirrored FATs, we need to read the active one */
	    sbi->fat += (fat.fat32.extended_flags & 0x0f) * sectors_per_fat;
	}

	/* FAT32: root directory is a cluster chain */
	sbi->root = sbi->data
	    + ((fat.fat32.root_cluster-2) << sbi->clust_shift);
    }
    sbi->clusters = clusters;

    /* fs UUID - serial number */
    if (FAT32 == sbi->fat_type)
	sbi->uuid = fat.fat32.num_serial;
    else
	sbi->uuid = fat.fat12_16.num_serial;

    /* Initialize the cache */
    cache_init(fs->fs_dev, fs->block_shift);

    return fs->block_shift;
}

static int vfat_copy_superblock(void *buf)
{
	struct fat_bpb fat;
	struct disk *disk;
	size_t sb_off;
	void *dst;
	int sb_len;

	disk = this_fs->fs_dev->disk;
	disk->rdwr_sectors(disk, &fat, 0, 1, 0);

	/* XXX: Find better sanity checks... */
	if (!fat.bxResSectors || !fat.bxFATs)
		return -1;

	sb_off = offsetof(struct fat_bpb, sector_size);
	sb_len = offsetof(struct fat_bpb, fat12_16) - sb_off \
		+ sizeof(fat.fat12_16);

	/*
	 * Only copy fields of the superblock we actually care about.
	 */
	dst = buf + sb_off;
	memcpy(dst, (void *)&fat + sb_off, sb_len);

	return 0;
}

#define FAT_UUID_LEN (4 + 1 + 4 + 1)
static char *vfat_fs_uuid(struct fs_info *fs)
{
    char *uuid = NULL;
    char *ptr;

    uuid = malloc(FAT_UUID_LEN);
    if (!uuid)
	return NULL;

    if (snprintf(uuid, FAT_UUID_LEN, "%04x-%04x",
	          (uint16_t)(FAT_SB(fs)->uuid >> 16),
	          (uint16_t)FAT_SB(fs)->uuid) < 0) {
	free(uuid);
	return NULL;
    }

    for (ptr = uuid; ptr && *ptr; ptr++)
	*ptr = toupper(*ptr);

    return uuid;
}

const struct fs_ops vfat_fs_ops = {
    .fs_name       = "vfat",
    .fs_flags      = FS_USEMEM | FS_THISIND,
    .fs_init       = vfat_fs_init,
    .searchdir     = NULL,
    .getfssec      = generic_getfssec,
    .close_file    = generic_close_file,
    .mangle_name   = vfat_mangle_name,
    .chdir_start   = generic_chdir_start,
    .open_config   = generic_open_config,
    .readdir       = vfat_readdir,
    .iget_root     = vfat_iget_root,
    .iget          = vfat_iget,
    .next_extent   = fat_next_extent,
    .copy_super    = vfat_copy_superblock,
    .fs_uuid       = vfat_fs_uuid,
};
