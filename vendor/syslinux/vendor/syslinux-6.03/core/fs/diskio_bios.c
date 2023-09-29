#include <core.h>
#include <com32.h>
#include <fs.h>
#include <ilog2.h>

#define RETRY_COUNT 6

static inline sector_t chs_max(const struct disk *disk)
{
    return (sector_t)disk->secpercyl << 10;
}

struct edd_rdwr_packet {
    uint16_t size;
    uint16_t blocks;
    far_ptr_t buf;
    uint64_t lba;
};

struct edd_disk_params {
    uint16_t  len;
    uint16_t  flags;
    uint32_t  phys_c;
    uint32_t  phys_h;
    uint32_t  phys_s;
    uint64_t  sectors;
    uint16_t  sector_size;
    far_ptr_t dpte;
    uint16_t  devpath_key;
    uint8_t   devpath_len;
    uint8_t   _pad1[3];
    char      bus_type[4];
    char      if_type[8];
    uint8_t   if_path[8];
    uint8_t   dev_path[16];
    uint8_t   _pad2;
    uint8_t   devpath_csum;	/* Depends on devpath_len! */
} __attribute__((packed));

static inline bool is_power_of_2(uint32_t x)
{
    return !(x & (x-1));
}

static int chs_rdwr_sectors(struct disk *disk, void *buf,
			    sector_t lba, size_t count, bool is_write)
{
    char *ptr = buf;
    char *tptr;
    size_t chunk, freeseg;
    int sector_shift = disk->sector_shift;
    uint32_t xlba = lba + disk->part_start; /* Truncated LBA (CHS is << 2 TB) */
    uint32_t t;
    uint32_t c, h, s;
    com32sys_t ireg, oreg;
    size_t done = 0;
    size_t bytes;
    int retry;
    uint32_t maxtransfer = disk->maxtransfer;

    if (lba + disk->part_start >= chs_max(disk))
	return 0;		/* Impossible CHS request */

    memset(&ireg, 0, sizeof ireg);

    ireg.eax.b[1] = 0x02 + is_write;
    ireg.edx.b[0] = disk->disk_number;

    while (count) {
	chunk = count;
	if (chunk > maxtransfer)
	    chunk = maxtransfer;

	freeseg = (0x10000 - ((size_t)ptr & 0xffff)) >> sector_shift;

	if ((size_t)buf <= 0xf0000 && freeseg) {
	    /* Can do a direct load */
	    tptr = ptr;
	} else {
	    /* Either accessing high memory or we're crossing a 64K line */
	    tptr = core_xfer_buf;
	    freeseg = (0x10000 - ((size_t)tptr & 0xffff)) >> sector_shift;
	}
	if (chunk > freeseg)
	    chunk = freeseg;

	s = xlba % disk->s;
	t = xlba / disk->s;
	h = t % disk->h;
	c = t / disk->h;

	if (chunk > (disk->s - s))
	    chunk = disk->s - s;

	bytes = chunk << sector_shift;

	if (tptr != ptr && is_write)
	    memcpy(tptr, ptr, bytes);

	ireg.eax.b[0] = chunk;
	ireg.ecx.b[1] = c;
	ireg.ecx.b[0] = ((c & 0x300) >> 2) | (s+1);
	ireg.edx.b[1] = h;
	ireg.ebx.w[0] = OFFS(tptr);
	ireg.es       = SEG(tptr);

	retry = RETRY_COUNT;

        for (;;) {
	    if (c < 1024) {
		dprintf("CHS[%02x]: %u @ %llu (%u/%u/%u) %04x:%04x %s %p\n",
			ireg.edx.b[0], chunk, xlba, c, h, s+1,
			ireg.es, ireg.ebx.w[0],
			(ireg.eax.b[1] & 1) ? "<-" : "->",
			ptr);

		__intcall(0x13, &ireg, &oreg);
		if (!(oreg.eflags.l & EFLAGS_CF))
		    break;

		dprintf("CHS: error AX = %04x\n", oreg.eax.w[0]);

		if (retry--)
		    continue;

		/*
		 * For any starting value, this will always end with
		 * ..., 1, 0
		 */
		chunk >>= 1;
		if (chunk) {
		    maxtransfer = chunk;
		    retry = RETRY_COUNT;
		    ireg.eax.b[0] = chunk;
		    continue;
		}
	    }

	    printf("CHS: Error %04x %s sector %llu (%u/%u/%u)\n",
		   oreg.eax.w[0],
		   is_write ? "writing" : "reading",
		   lba, c, h, s+1);
	    return done;	/* Failure */
	}

	bytes = chunk << sector_shift;

	if (tptr != ptr && !is_write)
	    memcpy(ptr, tptr, bytes);

	/* If we dropped maxtransfer, it eventually worked, so remember it */
	disk->maxtransfer = maxtransfer;

	ptr   += bytes;
	xlba  += chunk;
	count -= chunk;
	done  += chunk;
    }

    return done;
}

static int edd_rdwr_sectors(struct disk *disk, void *buf,
			    sector_t lba, size_t count, bool is_write)
{
    static __lowmem struct edd_rdwr_packet pkt;
    char *ptr = buf;
    char *tptr;
    size_t chunk, freeseg;
    int sector_shift = disk->sector_shift;
    com32sys_t ireg, oreg, reset;
    size_t done = 0;
    size_t bytes;
    int retry;
    uint32_t maxtransfer = disk->maxtransfer;

    memset(&ireg, 0, sizeof ireg);

    ireg.eax.b[1] = 0x42 + is_write;
    ireg.edx.b[0] = disk->disk_number;
    ireg.ds       = SEG(&pkt);
    ireg.esi.w[0] = OFFS(&pkt);

    memset(&reset, 0, sizeof reset);

    lba += disk->part_start;
    while (count) {
	chunk = count;
	if (chunk > maxtransfer)
	    chunk = maxtransfer;

	freeseg = (0x10000 - ((size_t)ptr & 0xffff)) >> sector_shift;

	if ((size_t)ptr <= 0xf0000 && freeseg) {
	    /* Can do a direct load */
	    tptr = ptr;
	} else {
	    /* Either accessing high memory or we're crossing a 64K line */
	    tptr = core_xfer_buf;
	    freeseg = (0x10000 - ((size_t)tptr & 0xffff)) >> sector_shift;
	}
	if (chunk > freeseg)
	    chunk = freeseg;

	bytes = chunk << sector_shift;

	if (tptr != ptr && is_write)
	    memcpy(tptr, ptr, bytes);

	retry = RETRY_COUNT;

	for (;;) {
	    pkt.size   = sizeof pkt;
	    pkt.blocks = chunk;
	    pkt.buf    = FAR_PTR(tptr);
	    pkt.lba    = lba;

	    dprintf("EDD[%02x]: %u @ %llu %04x:%04x %s %p\n",
		    ireg.edx.b[0], pkt.blocks, pkt.lba,
		    pkt.buf.seg, pkt.buf.offs,
		    (ireg.eax.b[1] & 1) ? "<-" : "->",
		    ptr);

	    __intcall(0x13, &ireg, &oreg);
	    if (!(oreg.eflags.l & EFLAGS_CF))
		break;

	    dprintf("EDD: error AX = %04x\n", oreg.eax.w[0]);

	    if (retry--)
		continue;

	    /*
	     * Some systems seem to get "stuck" in an error state when
	     * using EBIOS.  Doesn't happen when using CBIOS, which is
	     * good, since some other systems get timeout failures
	     * waiting for the floppy disk to spin up.
	     */
	    __intcall(0x13, &reset, NULL);

	    /* For any starting value, this will always end with ..., 1, 0 */
	    chunk >>= 1;
	    if (chunk) {
		maxtransfer = chunk;
		retry = RETRY_COUNT;
		continue;
	    }

	    /*
	     * Total failure.  There are systems which identify as
	     * EDD-capable but aren't; the known such systems return
	     * error code AH=1 (invalid function), but let's not
	     * assume that for now.
	     *
	     * Try to fall back to CHS.  If the LBA is absurd, the
	     * chs_max() test in chs_rdwr_sectors() will catch it.
	     */
	    done = chs_rdwr_sectors(disk, buf, lba - disk->part_start,
				    count, is_write);
	    if (done == (count << sector_shift)) {
		/* Successful, assume this is a CHS disk */
		disk->rdwr_sectors = chs_rdwr_sectors;
		return done;
	    }
	    printf("EDD: Error %04x %s sector %llu\n",
		   oreg.eax.w[0],
		   is_write ? "writing" : "reading",
		   lba);
	    return done;	/* Failure */
	}

	bytes = chunk << sector_shift;

	if (tptr != ptr && !is_write)
	    memcpy(ptr, tptr, bytes);

	/* If we dropped maxtransfer, it eventually worked, so remember it */
	disk->maxtransfer = maxtransfer;

	ptr   += bytes;
	lba   += chunk;
	count -= chunk;
	done  += chunk;
    }
    return done;
}

struct disk *bios_disk_init(void *private)
{
    static struct disk disk;
    struct bios_disk_private *priv = (struct bios_disk_private *)private;
    com32sys_t *regs = priv->regs;
    static __lowmem struct edd_disk_params edd_params;
    com32sys_t ireg, oreg;
    uint8_t devno = regs->edx.b[0];
    bool cdrom = regs->edx.b[1];
    sector_t part_start = regs->ecx.l | ((sector_t)regs->ebx.l << 32);
    uint16_t bsHeads = regs->esi.w[0];
    uint16_t bsSecPerTrack = regs->edi.w[0];
    uint32_t MaxTransfer = regs->ebp.l;
    bool ebios;
    int sector_size;
    unsigned int hard_max_transfer;

    memset(&ireg, 0, sizeof ireg);
    ireg.edx.b[0] = devno;

    if (cdrom) {
	/*
	 * The query functions don't work right on some CD-ROM stacks.
	 * Known affected systems: ThinkPad T22, T23.
	 */
	sector_size = 2048;
	ebios = true;
	hard_max_transfer = 32;
    } else {
	sector_size = 512;
	ebios = false;
	hard_max_transfer = 63;

	/* CBIOS parameters */
	disk.h = bsHeads;
	disk.s = bsSecPerTrack;

	if ((int8_t)devno < 0) {
	    /* Get hard disk geometry from BIOS */
	    
	    ireg.eax.b[1] = 0x08;
	    __intcall(0x13, &ireg, &oreg);
	    
	    if (!(oreg.eflags.l & EFLAGS_CF)) {
		disk.h = oreg.edx.b[1] + 1;
		disk.s = oreg.ecx.b[0] & 63;
	    }
	}

        memset(&ireg, 0, sizeof ireg);
	/* Get EBIOS support */
	ireg.eax.b[1] = 0x41;
	ireg.ebx.w[0] = 0x55aa;
	ireg.edx.b[0] = devno;
	ireg.eflags.b[0] = 0x3;	/* CF set */

	__intcall(0x13, &ireg, &oreg);
	
	if (!(oreg.eflags.l & EFLAGS_CF) &&
	    oreg.ebx.w[0] == 0xaa55 && (oreg.ecx.b[0] & 1)) {
	    ebios = true;
	    hard_max_transfer = 127;

	    /* Query EBIOS parameters */
	    /* The memset() is needed once this function can be called
	       more than once */
	    /* memset(&edd_params, 0, sizeof edd_params);  */
	    edd_params.len = sizeof edd_params;

            memset(&ireg, 0, sizeof ireg);
	    ireg.eax.b[1] = 0x48;
	    ireg.edx.b[0] = devno;
	    ireg.ds = SEG(&edd_params);
	    ireg.esi.w[0] = OFFS(&edd_params);
	    __intcall(0x13, &ireg, &oreg);

	    if (!(oreg.eflags.l & EFLAGS_CF) && oreg.eax.b[1] == 0) {
		if (edd_params.len < sizeof edd_params)
		    memset((char *)&edd_params + edd_params.len, 0,
			   sizeof edd_params - edd_params.len);

		if (edd_params.sector_size >= 512 &&
		    is_power_of_2(edd_params.sector_size))
		    sector_size = edd_params.sector_size;
	    }
	}

    }

    disk.disk_number   = devno;
    disk.sector_size   = sector_size;
    disk.sector_shift  = ilog2(sector_size);
    disk.part_start    = part_start;
    disk.secpercyl     = disk.h * disk.s;
    disk.rdwr_sectors  = ebios ? edd_rdwr_sectors : chs_rdwr_sectors;

    if (!MaxTransfer || MaxTransfer > hard_max_transfer)
	MaxTransfer = hard_max_transfer;

    disk.maxtransfer   = MaxTransfer;

    dprintf("disk %02x cdrom %d type %d sector %u/%u offset %llu limit %u\n",
	    devno, cdrom, ebios, sector_size, disk.sector_shift,
	    part_start, disk.maxtransfer);

    disk.private = private;
    return &disk;
}

void pm_fs_init(com32sys_t *regs)
{
	static struct bios_disk_private priv;

	priv.regs = regs;
	fs_init((const struct fs_ops **)regs->eax.l, (void *)&priv);
}
