/* -----------------------------------------------------------------------
 *
 *   Copyright 1999-2008 H. Peter Anvin - All Rights Reserved
 *   Copyright 2009-2011 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * pxe.h
 *
 * PXE opcodes
 *
 */
#ifndef PXE_H
#define PXE_H

#include <syslinux/pxe_api.h>
#include <syslinux/config.h>
#include <fcntl.h>		/* For OK_FLAGS_MASK */
#include "fs.h"			/* Mostly for FILENAME_MAX */

/*
 * Some basic defines...
 */
#define PKTBUF_SIZE     2048	/* Used mostly by the gPXE backend */

#define is_digit(c)     (((c) >= '0') && ((c) <= '9'))

#define BOOTP_OPTION_MAGIC  htonl(0x63825363)
#define MAC_MAX 32

/*
 * structures
 */
struct pxenv_t {
    uint8_t    signature[6];	/* PXENV+ */
    uint16_t   version;
    uint8_t    length;
    uint8_t    checksum;
    segoff16_t rmentry;
    uint32_t   pmoffset;
    uint16_t   pmselector;
    uint16_t   stackseg;
    uint16_t   stacksize;
    uint16_t   bc_codeseg;
    uint16_t   bc_codesize;
    uint16_t   bc_dataseg;
    uint16_t   bc_datasize;
    uint16_t   undidataseg;
    uint16_t   undidatasize;
    uint16_t   undicodeseg;
    uint16_t   undicodesize;
    segoff16_t pxeptr;
} __packed;

struct pxe_t {
    uint8_t    signature[4];	/* !PXE */
    uint8_t    structlength;
    uint8_t    structcksum;
    uint8_t    structrev;
    uint8_t    _pad1;
    segoff16_t undiromid;
    segoff16_t baseromid;
    segoff16_t entrypointsp;
    segoff16_t entrypointesp;
    segoff16_t statuscallout;
    uint8_t    _pad2;
    uint8_t    segdesccnt;
    uint16_t   firstselector;
    pxe_segdesc_t  seg[7];
} __packed;

enum pxe_segments {
    PXE_Seg_Stack         = 0,
    PXE_Seg_UNDIData      = 1,
    PXE_Seg_UNDICode      = 2,
    PXE_Seg_UNDICodeWrite = 3,
    PXE_Seg_BC_Data       = 4,
    PXE_Seg_BC_Code       = 5,
    PXE_Seg_BC_CodeWrite  = 6
};

struct bootp_t {
    uint8_t  opcode;        /* BOOTP/DHCP "opcode" */
    uint8_t  hardware;      /* ARP hreadware type */
    uint8_t  hardlen;       /* Hardware address length */
    uint8_t  gatehops;      /* Used by forwarders */
    uint32_t ident;         /* Transaction ID */
    uint16_t seconds;       /* Seconds elapsed */
    uint16_t flags;         /* Broadcast flags */
    uint32_t cip;           /* Cient IP */
    uint32_t yip;           /* "Your" IP */
    uint32_t sip;           /* Next Server IP */
    uint32_t gip;           /* Relay agent IP */
    uint8_t  macaddr[16];   /* Client MAC address */
    uint8_t  sname[64];     /* Server name (optional) */
    char     bootfile[128]; /* Boot file name */
    uint32_t option_magic;  /* Vendor option magic cookie */
    uint8_t  options[1260]; /* Vendor options */
} __attribute__ ((packed));

struct netconn;
struct netbuf;
struct efi_binding;

/*
 * Our inode private information -- this includes the packet buffer!
 */
struct pxe_conn_ops {
    void (*fill_buffer)(struct inode *inode);
    void (*close)(struct inode *inode);
    int (*readdir)(struct inode *inode, struct dirent *dirent);
};    

union net_private {
    struct net_private_lwip {
	struct netconn *conn;      /* lwip network connection */
	struct netbuf *buf;	   /* lwip cached buffer */
    } lwip;
    struct net_private_tftp {
	uint32_t remoteip;  	  /* Remote IP address (0 = disconnected) */
	uint16_t localport;   	  /* Local port number  (0=not in use) */
    } tftp;
    struct net_private_efi {
	struct efi_binding *binding; /* EFI binding for protocol */
	uint16_t localport;          /* Local port number (0=not in use) */
    } efi;
};

struct pxe_pvt_inode {
    union net_private net;	  /* Network stack private data */
    uint16_t tftp_remoteport;     /* Remote port number */
    uint32_t tftp_filepos;        /* bytes downloaded (including buffer) */
    uint32_t tftp_blksize;        /* Block size for this connection(*) */
    uint16_t tftp_bytesleft;      /* Unclaimed data bytes */
    uint16_t tftp_lastpkt;        /* Sequence number of last packet (HBO) */
    char    *tftp_dataptr;        /* Pointer to available data */
    uint8_t  tftp_goteof;         /* 1 if the EOF packet received */
    uint8_t  tftp_unused[3];      /* Currently unused */
    char    *tftp_pktbuf;         /* Packet buffer */
    struct inode *ctl;	          /* Control connection (for FTP) */
    const struct pxe_conn_ops *ops;
};

#define PVT(i) ((struct pxe_pvt_inode *)((i)->pvt))

/*
 * Variable externs
 */
extern struct syslinux_ipinfo IPInfo;

extern t_PXENV_UNDI_GET_INFORMATION pxe_undi_info;
extern t_PXENV_UNDI_GET_IFACE_INFO  pxe_undi_iface;

extern uint8_t MAC[];
extern char BOOTIFStr[];
extern uint8_t MAC_len;
extern uint8_t MAC_type;

extern uint8_t  DHCPMagic;
extern uint32_t RebootTime;

extern char boot_file[];
extern char path_prefix[];
extern char LocalDomain[];

extern uint32_t dns_server[];

extern uint16_t APIVer;
extern far_ptr_t PXEEntry;
extern uint8_t KeepPXE;

extern far_ptr_t InitStack;

extern bool have_uuid;
extern uint8_t uuid_type;
extern uint8_t uuid[];

struct url_info;
struct url_scheme {
    const char *name;
    void (*open)(struct url_info *, int, struct inode *, const char **);
    int ok_flags;
};
/* Flags which can be specified in url_scheme.ok_flags */
#define OK_FLAGS_MASK	(O_DIRECTORY|O_WRONLY)

extern const struct url_scheme url_schemes[];

/*
 * Compute the suitable gateway for a specific route -- too many
 * vendor PXE stacks don't do this correctly...
 */
static inline uint32_t gateway(uint32_t ip)
{
    if ((ip ^ IPInfo.myip) & IPInfo.netmask)
	return IPInfo.gateway;
    else
	return 0;
}

/*
 * functions
 */

/* pxeisr.inc */
extern uint8_t pxe_irq_vector;
extern void pxe_isr(void);
extern far_ptr_t pxe_irq_chain;
extern void pxe_poll(void);

/* isr.c */
void pxe_init_isr(void);
void pxe_start_isr(void);
int reset_pxe(void);

/* pxe.c */
struct url_info;
bool ip_ok(uint32_t);
int pxe_getc(struct inode *inode);
void free_socket(struct inode *inode);

/* undiif.c */
int undiif_start(uint32_t ip, uint32_t netmask, uint32_t gw);
void undiif_input(t_PXENV_UNDI_ISR *isr);

/* dhcp_options.c */
void parse_dhcp_options(const void *, int, uint8_t);
void parse_dhcp(const void *, size_t);

/* idle.c */
void pxe_idle_init(void);
void pxe_idle_cleanup(void);

/* tftp.c */
void tftp_open(struct url_info *url, int flags, struct inode *inode,
	       const char **redir);

/* gpxeurl.c */
void gpxe_open(struct inode *inode, const char *url);
#define GPXE 0

/* http.c */
void http_open(struct url_info *url, int flags, struct inode *inode,
	       const char **redir);

/* http_readdir.c */
int http_readdir(struct inode *inode, struct dirent *dirent);

/* ftp.c */
void ftp_open(struct url_info *url, int flags, struct inode *inode,
	      const char **redir);

/* ftp_readdir.c */
int ftp_readdir(struct inode *inode, struct dirent *dirent);

/* tcp.c */
const struct pxe_conn_ops tcp_conn_ops;

extern void gpxe_init(void);
extern int pxe_init(bool quiet);

#endif /* pxe.h */
