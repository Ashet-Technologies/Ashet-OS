#include <dprintf.h>
#include <stdio.h>
#include <string.h>
#include <core.h>
#include <fs.h>
#include <fcntl.h>
#include <sys/cpu.h>
#include "pxe.h"
#include "thread.h"
#include "url.h"
#include "tftp.h"
#include <net.h>

__lowmem t_PXENV_UNDI_GET_INFORMATION pxe_undi_info;
__lowmem t_PXENV_UNDI_GET_IFACE_INFO  pxe_undi_iface;

uint8_t MAC[MAC_MAX];		   /* Actual MAC address */
uint8_t MAC_len;                   /* MAC address len */
uint8_t MAC_type;                  /* MAC address type */

char boot_file[256];		   /* From DHCP */
char path_prefix[256];		   /* From DHCP */

bool have_uuid = false;

/*
 * Allocate a local UDP port structure and assign it a local port number.
 * Return the inode pointer if success, or null if failure
 */
static struct inode *allocate_socket(struct fs_info *fs)
{
    struct inode *inode = alloc_inode(fs, 0, sizeof(struct pxe_pvt_inode));

    if (!inode) {
	malloc_error("socket structure");
    } else {
	inode->mode = DT_REG;	/* No other types relevant for PXE */
    }

    return inode;
}

void free_socket(struct inode *inode)
{
    struct pxe_pvt_inode *socket = PVT(inode);

    free(socket->tftp_pktbuf);	/* If we allocated a buffer, free it now */
    free_inode(inode);
}

static void pxe_close_file(struct file *file)
{
    struct inode *inode = file->inode;
    struct pxe_pvt_inode *socket = PVT(inode);

    if (!inode)
	return;

    if (!socket->tftp_goteof) {
	socket->ops->close(inode);
    }

    free_socket(inode);
}

/*
 * Tests an IP address in _ip_ for validity; return with 0 for bad, 1 for good.
 * We used to refuse class E, but class E addresses are likely to become
 * assignable unicast addresses in the near future.
 *
 */
bool ip_ok(uint32_t ip)
{
    uint8_t ip_hi = (uint8_t)ip; /* First octet of the ip address */

    if (ip == 0xffffffff ||	/* Refuse the all-ones address */
	ip_hi == 0 ||		/* Refuse network zero */
	ip_hi == 127 ||		/* Refuse the loopback network */
	(ip_hi & 240) == 224)	/* Refuse class D */
	return false;

    return true;
}


/*
 * Take an IP address (in network byte order) in _ip_ and
 * output a dotted quad string to _dst_, returns the length
 * of the dotted quad ip string.
 *
 */
static int gendotquad(char *dst, uint32_t ip)
{
    return sprintf(dst, "%u.%u.%u.%u",
		   ((const uint8_t *)&ip)[0],
		   ((const uint8_t *)&ip)[1],
		   ((const uint8_t *)&ip)[2],
		   ((const uint8_t *)&ip)[3]);
}

/*
 * the ASM pxenv function wrapper, return 1 if error, or 0
 *
 */
__export int pxe_call(int opcode, void *data)
{
    static DECLARE_INIT_SEMAPHORE(pxe_sem, 1);
    extern void pxenv(void);
    com32sys_t regs;

    sem_down(&pxe_sem, 0);

#if 0
    dprintf("pxe_call op %04x data %p\n", opcode, data);
#endif

    memset(&regs, 0, sizeof regs);
    regs.ebx.w[0] = opcode;
    regs.es       = SEG(data);
    regs.edi.w[0] = OFFS(data);
    call16(pxenv, &regs, &regs);

    sem_up(&pxe_sem);

    return regs.eflags.l & EFLAGS_CF;  /* CF SET if fail */
}

/*
 * mangle a filename pointed to by _src_ into a buffer pointed
 * to by _dst_; ends on encountering any whitespace.
 *
 * This deliberately does not attempt to do any conversion of
 * pathname separators.
 *
 */
static void pxe_mangle_name(char *dst, const char *src)
{
    size_t len = FILENAME_MAX-1;

    while (len-- && not_whitespace(*src))
	*dst++ = *src++;

    *dst = '\0';
}

/*
 * Read a single character from the specified pxe inode.
 * Very useful for stepping through http streams and
 * parsing their headers.
 */
int pxe_getc(struct inode *inode)
{
    struct pxe_pvt_inode *socket = PVT(inode);
    unsigned char byte;

    while (!socket->tftp_bytesleft) {
	if (socket->tftp_goteof)
	    return -1;

	socket->ops->fill_buffer(inode);
    }

    byte = *socket->tftp_dataptr;
    socket->tftp_bytesleft -= 1;
    socket->tftp_dataptr += 1;

    return byte;
}

/*
 * Get a fresh packet if the buffer is drained, and we haven't hit
 * EOF yet.  The buffer should be filled immediately after draining!
 */
static void fill_buffer(struct inode *inode)
{
    struct pxe_pvt_inode *socket = PVT(inode);
    if (socket->tftp_bytesleft || socket->tftp_goteof)
        return;

    return socket->ops->fill_buffer(inode);
}


/**
 * getfssec: Get multiple clusters from a file, given the starting cluster.
 * In this case, get multiple blocks from a specific TCP connection.
 *
 * @param: fs, the fs_info structure address, in pxe, we don't use this.
 * @param: buf, buffer to store the read data
 * @param: openfile, TFTP socket pointer
 * @param: blocks, 512-byte block count; 0FFFFh = until end of file
 *
 * @return: the bytes read
 *
 */
static uint32_t pxe_getfssec(struct file *file, char *buf,
			     int blocks, bool *have_more)
{
    struct inode *inode = file->inode;
    struct pxe_pvt_inode *socket = PVT(inode);
    int count = blocks;
    int chunk;
    int bytes_read = 0;

    count <<= TFTP_BLOCKSIZE_LG2;
    while (count) {
        fill_buffer(inode); /* If we have no 'fresh' buffer, get it */
        if (!socket->tftp_bytesleft)
            break;

        chunk = count;
        if (chunk > socket->tftp_bytesleft)
            chunk = socket->tftp_bytesleft;
        socket->tftp_bytesleft -= chunk;
        memcpy(buf, socket->tftp_dataptr, chunk);
	socket->tftp_dataptr += chunk;
        buf += chunk;
        bytes_read += chunk;
        count -= chunk;
    }


    if (socket->tftp_bytesleft || (socket->tftp_filepos < inode->size)) {
	fill_buffer(inode);
        *have_more = 1;
    } else if (socket->tftp_goteof) {
        /*
         * The socket is closed and the buffer drained; the caller will
	 * call close_file and therefore free the socket.
         */
        *have_more = 0;
    }

    return bytes_read;
}

/*
 * Assign an IP address to a URL
 */
static void url_set_ip(struct url_info *url)
{
    url->ip = 0;
    if (url->host)
	url->ip = dns_resolv(url->host);
    if (!url->ip)
	url->ip = IPInfo.serverip;
}

/**
 * Open the specified connection
 *
 * @param:filename, the file we wanna open
 *
 * @out: open_file_t structure, stores in file->open_file
 * @out: the lenght of this file, stores in file->file_len
 *
 */
static void __pxe_searchdir(const char *filename, int flags, struct file *file);
extern uint16_t PXERetry;

static void pxe_searchdir(const char *filename, int flags, struct file *file)
{
    int i = PXERetry;

    do {
	dprintf("PXE: file = %p, retries left = %d: ", file, i);
	__pxe_searchdir(filename, flags, file);
	dprintf("%s\n", file->inode ? "ok" : "failed");
    } while (!file->inode && i--);
}
static void __pxe_searchdir(const char *filename, int flags, struct file *file)
{
    struct fs_info *fs = file->fs;
    struct inode *inode;
    char fullpath[2*FILENAME_MAX];
#if GPXE
    char urlsave[2*FILENAME_MAX];
#endif
    struct url_info url;
    const struct url_scheme *us = NULL;
    int redirect_count = 0;
    bool found_scheme = false;

    inode = file->inode = NULL;

    while (filename) {
	if (redirect_count++ > 5)
	    break;

	strlcpy(fullpath, filename, sizeof fullpath);
#if GPXE
	strcpy(urlsave, fullpath);
#endif
	parse_url(&url, fullpath);
	if (url.type == URL_SUFFIX) {
	    snprintf(fullpath, sizeof fullpath, "%s%s", fs->cwd_name, filename);
#if GPXE
	    strcpy(urlsave, fullpath);
#endif
	    parse_url(&url, fullpath);
	}

	inode = allocate_socket(fs);
	if (!inode)
	    return;			/* Allocation failure */
	
	url_set_ip(&url);
	
	filename = NULL;
	found_scheme = false;
	for (us = url_schemes; us->name; us++) {
	    if (!strcmp(us->name, url.scheme)) {
		if ((flags & ~us->ok_flags & OK_FLAGS_MASK) == 0)
		    us->open(&url, flags, inode, &filename);
		found_scheme = true;
		break;
	    }
	}

	/* filename here is set on a redirect */
    }

    if (!found_scheme) {
#if GPXE
	/* No URL scheme found, hand it to GPXE */
	gpxe_open(inode, urlsave);
#endif
    }

    if (inode->size) {
	file->inode = inode;
	file->inode->mode = (flags & O_DIRECTORY) ? DT_DIR : DT_REG;
    } else {
        free_socket(inode);
    }

    return;
}


/*
 * Store standard filename prefix
 */
static void get_prefix(void)
{
    int len;
    char *p;
    char c;

    if (!(DHCPMagic & 0x04)) {
	/* No path prefix option, derive from boot file */

	strlcpy(path_prefix, boot_file, sizeof path_prefix);
	len = strlen(path_prefix);
	p = &path_prefix[len - 1];
	
	while (len--) {
	    c = *p--;
	    c |= 0x20;
	    
	    c = (c >= '0' && c <= '9') ||
		(c >= 'a' && c <= 'z') ||
		(c == '.' || c == '-');
	    if (!c)
		break;
	};
	
	if (len < 0)
	    p --;
	
	*(p + 2) = 0;                /* Zero-terminate after delimiter */
    }

    ddprintf("TFTP prefix: %s\n", path_prefix);

    if (url_type(path_prefix) == URL_SUFFIX) {
	/*
	 * Construct a ::-style TFTP path.
	 *
	 * We may have moved out of the root directory at the time
	 * this function is invoked, but to maintain compatibility
	 * with versions of Syslinux < 5.00, path_prefix must be
	 * relative to "::".
	 */
	p = strdup(path_prefix);
	if (!p)
	    return;

	snprintf(path_prefix, sizeof path_prefix, "::%s", p);
	free(p);
    }

    chdir(path_prefix);
}

/*
 * realpath for PXE
 */
static size_t pxe_realpath(struct fs_info *fs, char *dst, const char *src,
			   size_t bufsize)
{
    return snprintf(dst, bufsize, "%s%s",
		    url_type(src) == URL_SUFFIX ? fs->cwd_name : "", src);
}

/*
 * chdir for PXE
 */
static int pxe_chdir(struct fs_info *fs, const char *src)
{
    /* The cwd for PXE is just a text prefix */
    enum url_type path_type = url_type(src);

    if (path_type == URL_SUFFIX)
	strlcat(fs->cwd_name, src, sizeof fs->cwd_name);
    else
	strlcpy(fs->cwd_name, src, sizeof fs->cwd_name);
    return 0;

    dprintf("cwd = \"%s\"\n", fs->cwd_name);
    return 0;
}

static int pxe_chdir_start(void)
{
	get_prefix();
	return 0;
}

/* Load the config file, return -1 if failed, or 0 */
static int pxe_open_config(struct com32_filedata *filedata)
{
    const char *cfgprefix = "pxelinux.cfg/";
    const char *default_str = "default";
    char *config_file;
    char *last;
    int tries = 8;

    chdir(path_prefix);
    if (DHCPMagic & 0x02) {
        /* We got a DHCP option, try it first */
	if (open_file(ConfigName, O_RDONLY, filedata) >= 0)
	    return 0;
    }

    /*
     * Have to guess config file name ...
     */
    config_file = stpcpy(ConfigName, cfgprefix);

    /* Try loading by UUID */
    if (sysappend_strings[SYSAPPEND_SYSUUID]) {
	strcpy(config_file, sysappend_strings[SYSAPPEND_SYSUUID]+8);
	if (open_file(ConfigName, O_RDONLY, filedata) >= 0)
            return 0;
    }

    /* Try loading by MAC address */
    strcpy(config_file, sysappend_strings[SYSAPPEND_BOOTIF]+7);
    if (open_file(ConfigName, O_RDONLY, filedata) >= 0)
        return 0;

    /* Nope, try hexadecimal IP prefixes... */
    sprintf(config_file, "%08X", ntohl(IPInfo.myip));
    last = &config_file[8];
    while (tries) {
        *last = '\0';        /* Zero-terminate string */
	if (open_file(ConfigName, O_RDONLY, filedata) >= 0)
            return 0;
        last--;           /* Drop one character */
        tries--;
    };

    /* Final attempt: "default" string */
    strcpy(config_file, default_str);
    if (open_file(ConfigName, O_RDONLY, filedata) >= 0)
        return 0;

    ddprintf("%-68s\n", "Unable to locate configuration file");
    kaboom();
}

/*
 * Generate the bootif string.
 */
static void make_bootif_string(void)
{
    static char bootif_str[7+3*(MAC_MAX+1)];
    const uint8_t *src;
    char *dst = bootif_str;
    int i;

    dst += sprintf(dst, "BOOTIF=%02x", MAC_type);
    src = MAC;
    for (i = MAC_len; i; i--)
	dst += sprintf(dst, "-%02x", *src++);

    sysappend_strings[SYSAPPEND_BOOTIF] = bootif_str;
}

/*
 * Generate an ip=<client-ip>:<boot-server-ip>:<gw-ip>:<netmask>
 * option into IPOption based on DHCP information in IPInfo.
 *
 */
static void genipopt(void)
{
    static char ip_option[3+4*16];
    const uint32_t *v = &IPInfo.myip;
    char *p;
    int i;

    p = stpcpy(ip_option, "ip=");

    for (i = 0; i < 4; i++) {
	p += gendotquad(p, *v++);
	*p++ = ':';
    }
    *--p = '\0';

    sysappend_strings[SYSAPPEND_IP] = ip_option;
}


/* Generate ip= option and print the ip adress */
static void ip_init(void)
{
    uint32_t ip = IPInfo.myip;
    char dot_quad_buf[16];

    genipopt();
    gendotquad(dot_quad_buf, ip);

    ip = ntohl(ip);
    ddprintf("My IP address seems to be %08X %s\n", ip, dot_quad_buf);
}

/*
 * Network-specific initialization
 */
static void network_init(void)
{
    net_parse_dhcp();

    make_bootif_string();
    /* If DMI and DHCP disagree, which one should we set? */
    if (have_uuid)
	sysappend_set_uuid(uuid);
    ip_init();

    /* print_sysappend(); */
    /*
     * Check to see if we got any PXELINUX-specific DHCP options; in particular,
     * if we didn't get the magic enable, do not recognize any other options.
     */
    if ((DHCPMagic & 1) == 0)
        DHCPMagic = 0;

    net_core_init();
}

/*
 * Initialize pxe fs
 *
 */
static int pxe_fs_init(struct fs_info *fs)
{
    (void)fs;    /* drop the compile warning message */

    /* Prepare for handling pxe interrupts */
    pxe_init_isr();

    /* This block size is actually arbitrary... */
    fs->sector_shift = fs->block_shift = TFTP_BLOCKSIZE_LG2;
    fs->sector_size  = fs->block_size  = 1 << TFTP_BLOCKSIZE_LG2;

    /* Find the PXE stack */
    if (pxe_init(false))
	kaboom();

    /* See if we also have a gPXE stack */
    gpxe_init();

    /* Network-specific initialization */
    network_init();

    /* Initialize network-card-specific idle handling */
    pxe_idle_init();

    /* Our name for the root */
    strcpy(fs->cwd_name, "::");

    return 0;
}

/*
 * Look to see if we are on an EFI CSM system.  Some EFI
 * CSM systems put the BEV stack in low memory, which means
 * a return to the PXE stack will crash the system.  However,
 * INT 18h works reliably, so in that case hack the stack and
 * point the "return address" to an INT 18h instruction.
 *
 * Hack the stack instead of the much simpler "just invoke INT 18h
 * if we want to reset", so that chainloading other NBPs will work.
 *
 * This manipulates the real-mode InitStack directly.  It relies on this
 * *not* being a currently active stack, i.e. the former
 * USE_PXE_PROVIDED_STACK no longer works.
 *
 * XXX: Disable this until we can find a better way to discriminate
 * between BIOSes that are broken on BEV return and BIOSes which are
 * broken on INT 18h.  Keying on the EFI CSM turns out to cause more
 * problems than it solves.
 */
extern far_ptr_t InitStack;

struct efi_struct {
    uint32_t magic;
    uint8_t  csum;
    uint8_t  len;
} __attribute__((packed));
#define EFI_MAGIC (('$' << 24)+('E' << 16)+('F' << 8)+'I')

static inline bool is_efi(const struct efi_struct *efi)
{
    /*
     * We don't verify the checksum, because it seems some CSMs leave
     * it at zero, sigh...
     */
    return (efi->magic == EFI_MAGIC) && (efi->len >= 83);
}

#if 0
static void install_int18_hack(void)
{
    static const uint8_t int18_hack[] =
    {
	0xcd, 0x18,			/* int $0x18 */
	0xea, 0xf0, 0xff, 0x00, 0xf0,	/* ljmpw $0xf000,$0xfff0 */
	0xf4				/* hlt */
    };
    uint16_t *retcode;

    retcode = GET_PTR(*(far_ptr_t *)((char *)GET_PTR(InitStack) + 44));

    /* Don't do this if the return already points to int $0x18 */
    if (*retcode != 0x18cd) {
	uint32_t efi_ptr;
	bool efi = false;

	for (efi_ptr = 0xe0000 ; efi_ptr < 0x100000 ; efi_ptr += 16) {
	    if (is_efi((const struct efi_struct *)efi_ptr)) {
		efi = true;
		break;
	    }
	}

	if (efi) {
	    uint8_t *src = GET_PTR(InitStack);
	    uint8_t *dst = src - sizeof int18_hack;

	    memmove(dst, src, 52);
	    memcpy(dst+52, int18_hack, sizeof int18_hack);
	    InitStack.offs -= sizeof int18_hack;

	    /* Clobber the return address */
	    *(uint16_t *)(dst+44) = OFFS_WRT(dst+52, InitStack.seg);
	    *(uint16_t *)(dst+46) = InitStack.seg;
	}
    }
}
#endif

static int pxe_readdir(struct file *file, struct dirent *dirent)
{
    struct inode *inode = file->inode;
    struct pxe_pvt_inode *socket = PVT(inode);

    if (socket->ops->readdir)
	return socket->ops->readdir(inode, dirent);
    else
	return -1;		/* No such operation */
}

const struct fs_ops pxe_fs_ops = {
    .fs_name       = "pxe",
    .fs_flags      = FS_NODEV,
    .fs_init       = pxe_fs_init,
    .searchdir     = pxe_searchdir,
    .chdir         = pxe_chdir,
    .realpath      = pxe_realpath,
    .getfssec      = pxe_getfssec,
    .close_file    = pxe_close_file,
    .mangle_name   = pxe_mangle_name,
    .chdir_start   = pxe_chdir_start,
    .open_config   = pxe_open_config,
    .readdir	   = pxe_readdir,
    .fs_uuid       = NULL,
};
