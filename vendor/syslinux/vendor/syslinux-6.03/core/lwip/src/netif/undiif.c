/**
 * @file
 * Ethernet Interface Skeleton
 *
 */

/*
 * Copyright (c) 2001-2004 Swedish Institute of Computer Science.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
 * SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
 * OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
 * IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
 * OF SUCH DAMAGE.
 *
 * This file is part of the lwIP TCP/IP stack.
 *
 * Author: Adam Dunkels <adam@sics.se>
 * Author: H. Peter Anvin <hpa@@zytor.com>
 * Author: Eric Biederman <ebiederm@xmission.com>
 *
 */

/*
 * This file is a skeleton for developing Ethernet network interface
 * drivers for lwIP. Add code to the low_level functions and do a
 * search-and-replace for the word "ethernetif" to replace it with
 * something that better describes your network interface.
 */

/* other headers include deprintf.h too early */
#define UNDIIF_ID_FULL_DEBUG (UNDIIF_ID_DEBUG | UNDIIF_DEBUG)

#if UNDIIF_ID_FULL_DEBUG
# ifndef DEBUG
#  define DEBUG 1
# endif
# ifndef DEBUG_PORT
#  define DEBUG_PORT 0x3f8
# endif
#endif /* UNDIIF_ID_FULL_DEBUG */

#include <core.h>

#include "lwip/opt.h"

#define LWIP_UNDIIF_DBG(debug) \
    ( ((debug) & LWIP_DBG_ON) && \
      ((debug) & LWIP_DBG_TYPES_ON) && \
      (((debug) & LWIP_DBG_MASK_LEVEL) >= LWIP_DBG_MIN_LEVEL) )

#include "lwip/def.h"
#include "lwip/mem.h"
#include "lwip/pbuf.h"
#include "lwip/sys.h"
#include <lwip/stats.h>
#include <lwip/snmp.h>
#include "netif/etharp.h"
#include "netif/ppp_oe.h"
#include "lwip/netifapi.h"
#include "lwip/tcpip.h"
#include "../../../fs/pxe/pxe.h"

#include <inttypes.h>
#include <string.h>
#include <syslinux/pxe_api.h>
#include <dprintf.h>

/* debug extras */
#include "ipv4/lwip/icmp.h"
#include "lwip/tcp_impl.h"
#include "lwip/udp.h"

#if LWIP_AUTOIP
#error "AUTOIP not supported"
#endif
#if ETH_PAD_SIZE
#error "ETH_PAD_SIZE not supported"
#endif
#if NETIF_MAX_HWADDR_LEN != MAC_MAX
#error "hwaddr_len mismatch"
#endif

/** the time an ARP entry stays valid after its last update,
 *  for ARP_TMR_INTERVAL = 5000, this is
 *  (240 * 5) seconds = 20 minutes.
 */
#define UNDIARP_MAXAGE 240
/** the time an ARP entry stays pending after first request,
 *  for ARP_TMR_INTERVAL = 5000, this is
 *  (2 * 5) seconds = 10 seconds.
 * 
 *  @internal Keep this number at least 2, otherwise it might
 *  run out instantly if the timeout occurs directly after a request.
 */
#define UNDIARP_MAXPENDING 2

typedef u8_t hwaddr_t[NETIF_MAX_HWADDR_LEN];

#ifdef PACK_STRUCT_USE_INCLUDES
#  include "arch/bpstruct.h"
#endif
PACK_STRUCT_BEGIN
/** the ARP message */
struct arp_hdr {
  PACK_STRUCT_FIELD(u16_t hwtype);
  PACK_STRUCT_FIELD(u16_t proto);
  PACK_STRUCT_FIELD(u8_t  hwlen);
  PACK_STRUCT_FIELD(u8_t  protolen);
  PACK_STRUCT_FIELD(u16_t opcode);
} PACK_STRUCT_STRUCT;
PACK_STRUCT_END
#ifdef PACK_STRUCT_USE_INCLUDES
#  include "arch/epstruct.h"
#endif

static inline int arp_hdr_len(struct netif *netif)
{
  return sizeof(struct arp_hdr) + (netif->hwaddr_len + sizeof(uint32_t))*2;
}

enum undiarp_state {
  UNDIARP_STATE_EMPTY = 0,
  UNDIARP_STATE_PENDING,
  UNDIARP_STATE_STABLE
};

struct undiarp_entry {
#if ARP_QUEUEING
  /** 
   * Pointer to queue of pending outgoing packets on this ARP entry.
   */
  struct etharp_q_entry *q;
#endif
  struct ip_addr ipaddr;
  u8_t hwaddr[NETIF_MAX_HWADDR_LEN];
  enum undiarp_state state;
  u8_t ctime;
  struct netif *netif;
};

#define PKTBUF_SIZE	2048

/* Define those to better describe your network interface. */
#define IFNAME0 'u'
#define IFNAME1 'n'

static struct netif undi_netif;
static struct undiarp_entry arp_table[ARP_TABLE_SIZE];
#if !LWIP_NETIF_HWADDRHINT
static u8_t undiarp_cached_entry;
#endif

/**
 * Try hard to create a new entry - we want the IP address to appear in
 * the cache (even if this means removing an active entry or so). */
#define UNDIARP_TRY_HARD 1
#define UNDIARP_FIND_ONLY  2

#define UNIDIF_ID_STRLEN 300


static inline bool undi_is_ethernet(struct netif *netif)
{
   (void)netif;
   return MAC_type == ETHER_TYPE;
}

#if 0
static void print_pbuf(struct pbuf *p)
{
   struct pbuf *q;
   int off;

   for( off = 0, q = p; q != NULL; q = q->next) {
       unsigned char *byte, *end;
       byte = q->payload;
       end = byte + q->len;
       for (; byte < end; byte++, off++ ) {
	   if ((off & 0xf) == 0) {
	       printf("%04x: ", off);
	   }
	   printf("%02x ", *byte);
	   if ((off & 0xf) == 0xf) {
	       printf("\n");
	   }
       }
   }
   printf("\n");
}
#endif

#if 0
static void print_arp_pbuf(struct netif *netif, struct pbuf *p)
{
  struct arp_hdr *hdr;
  u8_t *hdr_ptr;
  int i;

  hdr = p->payload;
  hdr_ptr = (unsigned char *)(hdr + 1);
  /* Fixed fields */
  printf("arp: %04x %04x %04x %04x ",
	  hdr->hwtype,
	  hdr->proto,
	  hdr->_hwlen_protolen);
  /* Source hardware address */
  for(i = 0; i < netif->hwaddr_len; i++, hdr_ptr++) {
    printf("%02x%c", *hdr_ptr,(i +1) == netif->hwaddr_len?' ':':');
  }
  /* Source ip address */
  printf("%d.%d.%d.%d ", hdr_ptr[0], hdr_ptr[1], hdr_ptr[2], hdr_ptr[3]);
  hdr_ptr += 4;
  /* Destination hardware address */
  for(i = 0; i < netif->hwaddr_len; i++, hdr_ptr++) {
    printf("%02x%c", *hdr_ptr, (i +1) == netif->hwaddr_len?' ':':');
  }
  /* Destination ip address */
  printf("%d.%d.%d.%d ", hdr_ptr[0], hdr_ptr[1], hdr_ptr[2], hdr_ptr[3]);
  hdr_ptr += 4;
}
#endif

#if LWIP_UNDIIF_DBG(UNDIIF_ID_FULL_DEBUG)
int snprintf_eth_hdr(char *str, size_t size, char head[],
		     struct eth_hdr *ethhdr, char dir, char status,
		     char tail[])
{
  u8_t *d = ethhdr->dest.addr;
  u8_t *s = ethhdr->src.addr;
  return snprintf(str, size,
		"%s: d:%02x:%02x:%02x:%02x:%02x:%02x"
		" s:%02x:%02x:%02x:%02x:%02x:%02x"
		" t:%4hx %c%c%s\n", head,
		d[0], d[1], d[2], d[3], d[4], d[5],
		s[0], s[1], s[2], s[3], s[4], s[5],
		(unsigned)htons(ethhdr->type),
		dir, status, tail);
}

int snprintf_arp_hdr(char *str, size_t size, char head[],
		      struct eth_hdr *ethhdr, char dir,
		      char status, char tail[])
{
  struct etharp_hdr *arphdr;
  u8_t *d, *s;
  struct ip_addr *sip, *dip;
  if (ntohs(ethhdr->type) == ETHTYPE_ARP) {
    arphdr = (struct etharp_hdr *)((void *)ethhdr + 14);
    d = arphdr->dhwaddr.addr;
    s = arphdr->shwaddr.addr;
    sip = (struct ip_addr *) &(arphdr->sipaddr);
    dip = (struct ip_addr *) &(arphdr->dipaddr);
    return snprintf(str, size,
		"%s: s:%02x:%02x:%02x:%02x:%02x:%02x"
		" %3d.%3d.%3d.%3d"
		" %02x:%02x:%02x:%02x:%02x:%02x"
		" %3d.%3d.%3d.%3d"
		" %c%c%s\n", head,
		s[0], s[1], s[2], s[3], s[4], s[5],
		ip4_addr1(sip), ip4_addr2(sip),
		ip4_addr3(sip), ip4_addr4(sip),
		d[0], d[1], d[2], d[3], d[4], d[5],
		ip4_addr1(dip), ip4_addr2(dip),
		ip4_addr3(dip), ip4_addr4(dip),
		dir, status, tail);
  } else {
    return 0;
  }
}
 
int snprintf_ip_hdr(char *str, size_t size, char head[],
		     struct eth_hdr *ethhdr, char dir,
		     char status, char tail[])
{
  struct ip_hdr *iphdr;
  if (ntohs(ethhdr->type) == ETHTYPE_IP) {
    iphdr = (struct ip_hdr *)((void *)ethhdr + 14);
    return snprintf(str, size,
		 "%s: s:%3d.%3d.%3d.%3d %3d.%3d.%3d.%3d l:%5d"
		 " i:%04x p:%04x c:%04x hl:%3d"
		 " %c%c%s\n", head,
		  ip4_addr1(&iphdr->src), ip4_addr2(&iphdr->src),
		  ip4_addr3(&iphdr->src), ip4_addr4(&iphdr->src),
		  ip4_addr1(&iphdr->dest), ip4_addr2(&iphdr->dest),
		  ip4_addr3(&iphdr->dest), ip4_addr4(&iphdr->dest),
		  ntohs(IPH_LEN(iphdr)), ntohs(IPH_ID(iphdr)),
		  IPH_PROTO(iphdr), ntohs(IPH_CHKSUM(iphdr)),
		  (IPH_HL(iphdr) << 2),
		  dir, status, tail);
  } else {
    return 0;
  }
}

int snprintf_icmp_hdr(char *str, size_t size, char head[],
		       struct eth_hdr *ethhdr, char dir,
		       char status, char tail[])
{
  struct ip_hdr *iphdr;
  struct icmp_echo_hdr *icmphdr;
  if (ntohs(ethhdr->type) == ETHTYPE_IP) {
    iphdr = (struct ip_hdr *)((void *)ethhdr + 14);
    if (IPH_PROTO(iphdr) == IP_PROTO_ICMP) {
      icmphdr = (struct icmp_echo_hdr *)((void *)iphdr + (IPH_HL(iphdr) << 2));
      return snprintf(str, size,
		 "%s: t:%02x c:%02x k:%04x"
		   " i:%04x s:%04x "
		   " %c%c%s\n", head,
		   icmphdr->type, icmphdr->code, ntohs(icmphdr->chksum),
		   ntohs(icmphdr->id), ntohs(icmphdr->seqno),
		    dir, status, tail);
    } else {
      return 0;
    }
  } else {
    return 0;
  }
}
 
int snprintf_tcp_hdr(char *str, size_t size, char head[],
		     struct eth_hdr *ethhdr, char dir,
		     char status, char tail[])
{
  struct ip_hdr *iphdr;
  struct tcp_hdr *tcphdr;
  if (ntohs(ethhdr->type) == ETHTYPE_IP) {
    iphdr = (struct ip_hdr *)((void *)ethhdr + 14);
    if (IPH_PROTO(iphdr) == IP_PROTO_TCP) {
      tcphdr = (struct tcp_hdr *)((void *)iphdr + (IPH_HL(iphdr) << 2));
      u16_t lenfl = ntohs(tcphdr->_hdrlen_rsvd_flags);
      return snprintf(str, size,
		 "%s: s:%5d %5d q:%08x a:%08x lf:%04x k:%04x"
		   " %c%c%s\n", head,
		    ntohs(tcphdr->src), ntohs(tcphdr->dest),
		    ntohl(tcphdr->seqno), ntohl(tcphdr->ackno),
		    lenfl, ntohs(tcphdr->chksum),
		    dir, status, tail);
    } else {
      return 0;
    }
  } else {
    return 0;
  }
}
 
int snprintf_udp_hdr(char *str, size_t size, char head[],
		      struct eth_hdr *ethhdr, char dir,
		      char status, char tail[])
{
  struct ip_hdr *iphdr;
  struct udp_hdr *udphdr;
  if (ntohs(ethhdr->type) == ETHTYPE_IP) {
    iphdr = (struct ip_hdr *)((void *)ethhdr + 14);
    if (IPH_PROTO(iphdr) == IP_PROTO_UDP) {
      udphdr = (struct udp_hdr *)((void *)iphdr + (IPH_HL(iphdr) << 2));
      return snprintf(str, size,
		 "%s: s:%5d %5d l:%d c:%04x"
		   " %c%c%s\n", head,
		    ntohs(udphdr->src), ntohs(udphdr->dest),
		    ntohs(udphdr->len), ntohs(udphdr->chksum),
		    dir, status, tail);
    } else {
      return 0;
    }
  } else {
    return 0;
  }
}
#endif /* UNDIIF_ID_FULL_DEBUG */

/**
 * In this function, the hardware should be initialized.
 * Called from undiif_init().
 *
 * @param netif the already initialized lwip network interface structure
 *        for this undiif
 */
static void
low_level_init(struct netif *netif)
{
  static __lowmem t_PXENV_UNDI_OPEN undi_open;
  int i;

  /* MAC_type and MAC_len should always match what is returned by
   * PXENV_UNDI_GET_INFORMATION.  At the moment the both seem to be
   * reliable but if they disagree that is a sign of a nasty bug
   * somewhere so abort.
   */
  /* If we are in conflict abort */
  if (MAC_type != pxe_undi_info.HwType) {
    printf("HwType conflicit: %u != %u\n",
	    MAC_type, pxe_undi_info.HwType);
    kaboom();
  }
  if (MAC_len != pxe_undi_info.HwAddrLen) {
     printf("HwAddrLen conflict: %u != %u\n",
	     MAC_len, pxe_undi_info.HwAddrLen);
     kaboom();
  }

  /* set MAC hardware address length */
  netif->hwaddr_len = MAC_len;

  /* set MAC hardware address */
  memcpy(netif->hwaddr, MAC, MAC_len);

  /* maximum transfer unit */
  netif->mtu = pxe_undi_info.MaxTranUnit;

  dprintf("UNDI: hw address");
  for (i = 0; i < netif->hwaddr_len; i++)
      dprintf("%c%02x", i ? ':' : ' ', (uint8_t)netif->hwaddr[i]);
  dprintf("\n");

  /* device capabilities */
  netif->flags = NETIF_FLAG_BROADCAST | NETIF_FLAG_LINK_UP;
  /* don't set NETIF_FLAG_ETHARP if this device is not an ethernet one */
  if (undi_is_ethernet(netif))
    netif->flags |= NETIF_FLAG_ETHARP;

  /* Install the interrupt vector */
  pxe_start_isr();

  /* Open the UNDI stack - you'd think the BC would have done this... */
  undi_open.PktFilter = 0x0003;	/* FLTR_DIRECTED | FLTR_BRDCST */
  pxe_call(PXENV_UNDI_OPEN, &undi_open);
}

/**
 * This function should do the actual transmission of the packet. The packet is
 * contained in the pbuf that is passed to the function. This pbuf
 * might be chained.
 *
 * @param netif the lwip network interface structure for this undiif
 * @param p the MAC packet to send (e.g. IP packet including MAC addresses and type)
 * @return ERR_OK if the packet could be sent
 *         an err_t value if the packet couldn't be sent
 *
 * @note Returning ERR_MEM here if a DMA queue of your MAC is full can lead to
 *       strange results. You might consider waiting for space in the DMA queue
 *       to become availale since the stack doesn't retry to send a packet
 *       dropped because of memory failure (except for the TCP timers).
 */
extern volatile uint32_t pxe_irq_count;
extern volatile uint8_t  pxe_need_poll;

static err_t
undi_transmit(struct netif *netif, struct pbuf *pbuf,
  hwaddr_t *dest, uint16_t undi_protocol)
{
  struct pxe_xmit {
    t_PXENV_UNDI_TRANSMIT xmit;
    t_PXENV_UNDI_TBD tbd;
  };
  static __lowmem struct pxe_xmit pxe;
  static __lowmem hwaddr_t low_dest;
  static __lowmem char pkt_buf[PKTBUF_SIZE];
  uint32_t now;
  static uint32_t first_xmit;
#if LWIP_UNDIIF_DBG(UNDIIF_ID_FULL_DEBUG)
  char *str = malloc(UNIDIF_ID_STRLEN);
  int strpos = 0;
  struct eth_hdr *ethhdr = pbuf->payload;


  strpos += snprintf(str + strpos, UNIDIF_ID_STRLEN - strpos,
		     "undi xmit thd '%s'\n", current()->name);
  strpos += snprintf_eth_hdr(str + strpos, UNIDIF_ID_STRLEN - strpos,
			      "undi", ethhdr, 'x', '0', "");
  strpos += snprintf_arp_hdr(str + strpos, UNIDIF_ID_STRLEN - strpos,
			      "  arp", ethhdr, 'x', '0', "");
  strpos += snprintf_ip_hdr(str + strpos, UNIDIF_ID_STRLEN - strpos,
			      "  ip", ethhdr, 'x', '0', "");
  strpos += snprintf_icmp_hdr(str + strpos, UNIDIF_ID_STRLEN - strpos,
			      "    icmp", ethhdr, 'x', '0', "");
  strpos += snprintf_tcp_hdr(str + strpos, UNIDIF_ID_STRLEN - strpos,
			      "    tcp", ethhdr, 'x', '0', "");
  strpos += snprintf_udp_hdr(str + strpos, UNIDIF_ID_STRLEN - strpos,
			      "    udp", ethhdr, 'x', '0', "");
  LWIP_DEBUGF(UNDIIF_ID_FULL_DEBUG, ("%s", str));
  free(str);
#endif /* UNDIIF_ID_FULL_DEBUG */

  /* Drop jumbo frames */
  if ((pbuf->tot_len > sizeof(pkt_buf)) || (pbuf->tot_len > netif->mtu))
    return ERR_ARG;

  if (__unlikely(!pxe_irq_count)) {
      now = ms_timer();
      if (!first_xmit) {
	  first_xmit = now;
      } else if (now - first_xmit > 3000) {
	  /* 3 seconds after first transmit, and no interrupts */
	  LWIP_PLATFORM_DIAG(("undiif: forcing polling\n"));
	  asm volatile("orb $1,%0" : "+m" (pxe_need_poll));
	  asm volatile("incl %0" : "+m" (pxe_irq_count));
      }
  }

  pbuf_copy_partial( pbuf, pkt_buf, pbuf->tot_len, 0);
  if (dest)
    memcpy(low_dest, dest, netif->hwaddr_len);

  do {
    memset(&pxe, 0, sizeof pxe);

    pxe.xmit.Protocol = undi_protocol;
    pxe.xmit.XmitFlag = dest? XMT_DESTADDR : XMT_BROADCAST;
    pxe.xmit.DestAddr = FAR_PTR(&low_dest);
    pxe.xmit.TBD = FAR_PTR(&pxe.tbd);
    pxe.tbd.ImmedLength = pbuf->tot_len;
    pxe.tbd.Xmit = FAR_PTR(pkt_buf);

    pxe_call(PXENV_UNDI_TRANSMIT, &pxe.xmit);
  } while (pxe.xmit.Status == PXENV_STATUS_OUT_OF_RESOURCES);

  LINK_STATS_INC(link.xmit);

  return ERR_OK;
}

static err_t
undi_send_unknown(struct netif *netif, struct pbuf *pbuf)
{
  return undi_transmit(netif, pbuf, NULL, P_UNKNOWN);
}

static err_t
undi_send_ip(struct netif *netif, struct pbuf *pbuf, hwaddr_t  *dst)
{
  return undi_transmit(netif, pbuf, dst, P_IP);
}

static err_t
undi_send_arp(struct netif *netif, struct pbuf *pbuf, hwaddr_t  *dst)
{
  return undi_transmit(netif, pbuf, dst, P_ARP);
}

/**
 * Send an ARP request packet asking for ipaddr.
 *
 * @param netif the lwip network interface on which to send the request
 * @param ipaddr the IP address for which to ask
 * @return ERR_OK if the request has been sent
 *         ERR_MEM if the ARP packet couldn't be allocated
 *         any other err_t on failure
 */
static err_t
undiarp_request(struct netif *netif, struct ip_addr *ipaddr)
{
  struct pbuf *p;
  err_t result = ERR_OK;
  struct arp_hdr *hdr;
  u8_t *hdr_ptr;

  LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiarp_request: sending ARP request.\n"));

  /* allocate a pbuf for the outgoing ARP request packet */
  p = pbuf_alloc(PBUF_RAW, arp_hdr_len(netif), PBUF_RAM);
  /* could allocate a pbuf for an ARP request? */
  if (p == NULL) {
    LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE | LWIP_DBG_LEVEL_SERIOUS,
      ("undiarp_raw: could not allocate pbuf for ARP request.\n"));
    ETHARP_STATS_INC(etharp.memerr);
    return ERR_MEM;
  }
  LWIP_ASSERT("check that first pbuf can hold arp_hdr_len bytesr",
              (p->len >= arp_hdr_len(netif)));

  hdr = p->payload;
  LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiarp_request: sending raw ARP packet.\n"));
  hdr->opcode = htons(ARP_REQUEST);
  hdr->hwtype = htons(MAC_type);
  hdr->proto = htons(ETHTYPE_IP);
  hdr->hwlen = netif->hwaddr_len;
  hdr->protolen = sizeof(struct ip_addr);

  hdr_ptr = (unsigned char *)(hdr + 1);
  memcpy(hdr_ptr, netif->hwaddr, netif->hwaddr_len);
  hdr_ptr += netif->hwaddr_len;
  memcpy(hdr_ptr, &netif->ip_addr, 4);
  hdr_ptr += 4;
    memset(hdr_ptr, 0, netif->hwaddr_len);
  hdr_ptr += netif->hwaddr_len;
  memcpy(hdr_ptr, ipaddr, 4);
  
  /* send ARP query */
  result = undi_send_arp(netif, p, NULL);
  ETHARP_STATS_INC(etharp.xmit);
  /* free ARP query packet */
  pbuf_free(p);
  p = NULL;
  /* could not allocate pbuf for ARP request */

  return result;
}

#if ARP_QUEUEING
/**
 * Free a complete queue of etharp entries
 *
 * @param q a qeueue of etharp_q_entry's to free
 */
static void
free_undiarp_q(struct etharp_q_entry *q)
{
  struct etharp_q_entry *r;
  LWIP_ASSERT("q != NULL", q != NULL);
  LWIP_ASSERT("q->p != NULL", q->p != NULL);
  while (q) {
    r = q;
    q = q->next;
    LWIP_ASSERT("r->p != NULL", (r->p != NULL));
    pbuf_free(r->p);
    memp_free(MEMP_ARP_QUEUE, r);
  }
}
#endif

/**
 * Clears expired entries in the ARP table.
 *
 * This function should be called every ETHARP_TMR_INTERVAL microseconds (5 seconds),
 * in order to expire entries in the ARP table.
 */
void
undiarp_tmr(void)
{
  u8_t i;

  LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG, ("undiarp_timer\n"));
  /* remove expired entries from the ARP table */
  for (i = 0; i < ARP_TABLE_SIZE; ++i) {
    arp_table[i].ctime++;
    if (((arp_table[i].state == UNDIARP_STATE_STABLE) &&
         (arp_table[i].ctime >= UNDIARP_MAXAGE)) ||
        ((arp_table[i].state == UNDIARP_STATE_PENDING)  &&
         (arp_table[i].ctime >= UNDIARP_MAXPENDING))) {
         /* pending or stable entry has become old! */
      LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG , ("undiarp_timer: expired %s entry %"U16_F".\n",
           arp_table[i].state == UNDIARP_STATE_STABLE ? "stable" : "pending", (u16_t)i));
      /* clean up entries that have just been expired */
      /* remove from SNMP ARP index tree */
      snmp_delete_arpidx_tree(arp_table[i].netif, &arp_table[i].ipaddr);
#if ARP_QUEUEING
      /* and empty packet queue */
      if (arp_table[i].q != NULL) {
        /* remove all queued packets */
        LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG , ("undiarp_timer: freeing entry %"U16_F", packet queue %p.\n", (u16_t)i, (void *)(arp_table[i].q)));
        free_undiarp_q(arp_table[i].q);
        arp_table[i].q = NULL;
      }
#endif
      /* recycle entry for re-use */      
      arp_table[i].state = UNDIARP_STATE_EMPTY;
    }
#if ARP_QUEUEING
    /* still pending entry? (not expired) */
    if (arp_table[i].state == UNDIARP_STATE_PENDING) {
        /* resend an ARP query here? */
    }
#endif
  }
}

/**
 * Search the ARP table for a matching or new entry.
 * 
 * If an IP address is given, return a pending or stable ARP entry that matches
 * the address. If no match is found, create a new entry with this address set,
 * but in state ETHARP_EMPTY. The caller must check and possibly change the
 * state of the returned entry.
 * 
 * If ipaddr is NULL, return a initialized new entry in state ETHARP_EMPTY.
 * 
 * In all cases, attempt to create new entries from an empty entry. If no
 * empty entries are available and UNDIARP_TRY_HARD flag is set, recycle
 * old entries. Heuristic choose the least important entry for recycling.
 *
 * @param ipaddr IP address to find in ARP cache, or to add if not found.
 * @param flags
 * - UNDIARP_TRY_HARD: Try hard to create a entry by allowing recycling of
 * active (stable or pending) entries.
 *  
 * @return The ARP entry index that matched or is created, ERR_MEM if no
 * entry is found or could be recycled.
 */
static s8_t
#if LWIP_NETIF_HWADDRHINT
find_entry(struct ip_addr *ipaddr, u8_t flags, struct netif *netif)
#else /* LWIP_NETIF_HWADDRHINT */
find_entry(struct ip_addr *ipaddr, u8_t flags)
#endif /* LWIP_NETIF_HWADDRHINT */
{
  s8_t old_pending = ARP_TABLE_SIZE, old_stable = ARP_TABLE_SIZE;
  s8_t empty = ARP_TABLE_SIZE;
  u8_t i = 0, age_pending = 0, age_stable = 0;
#if ARP_QUEUEING
  /* oldest entry with packets on queue */
  s8_t old_queue = ARP_TABLE_SIZE;
  /* its age */
  u8_t age_queue = 0;
#endif

  /* First, test if the last call to this function asked for the
   * same address. If so, we're really fast! */
  if (ipaddr) {
    /* ipaddr to search for was given */
#if LWIP_NETIF_HWADDRHINT
    if ((netif != NULL) && (netif->addr_hint != NULL)) {
      /* per-pcb cached entry was given */
      u8_t per_pcb_cache = *(netif->addr_hint);
      if ((per_pcb_cache < ARP_TABLE_SIZE) && arp_table[per_pcb_cache].state == UNDIARP_STATE_STABLE) {
        /* the per-pcb-cached entry is stable */
        if (ip_addr_cmp(ipaddr, &arp_table[per_pcb_cache].ipaddr)) {
          /* per-pcb cached entry was the right one! */
          ETHARP_STATS_INC(etharp.cachehit);
          return per_pcb_cache;
        }
      }
    }
#else /* #if LWIP_NETIF_HWADDRHINT */
    if (arp_table[undiarp_cached_entry].state == UNDIARP_STATE_STABLE) {
      /* the cached entry is stable */
      if (ip_addr_cmp(ipaddr, &arp_table[undiarp_cached_entry].ipaddr)) {
        /* cached entry was the right one! */
        ETHARP_STATS_INC(etharp.cachehit);
        return undiarp_cached_entry;
      }
    }
#endif /* #if LWIP_NETIF_HWADDRHINT */
  }

  /**
   * a) do a search through the cache, remember candidates
   * b) select candidate entry
   * c) create new entry
   */

  /* a) in a single search sweep, do all of this
   * 1) remember the first empty entry (if any)
   * 2) remember the oldest stable entry (if any)
   * 3) remember the oldest pending entry without queued packets (if any)
   * 4) remember the oldest pending entry with queued packets (if any)
   * 5) search for a matching IP entry, either pending or stable
   *    until 5 matches, or all entries are searched for.
   */

  for (i = 0; i < ARP_TABLE_SIZE; ++i) {
    /* no empty entry found yet and now we do find one? */
    if ((empty == ARP_TABLE_SIZE) && (arp_table[i].state == UNDIARP_STATE_EMPTY)) {
      LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG , ("find_entry: found empty entry %"U16_F"\n", (u16_t)i));
      /* remember first empty entry */
      empty = i;
    }
    /* pending entry? */
    else if (arp_table[i].state == UNDIARP_STATE_PENDING) {
      /* if given, does IP address match IP address in ARP entry? */
      if (ipaddr && ip_addr_cmp(ipaddr, &arp_table[i].ipaddr)) {
        LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("find_entry: found matching pending entry %"U16_F"\n", (u16_t)i));
        /* found exact IP address match, simply bail out */
#if LWIP_NETIF_HWADDRHINT
        NETIF_SET_HINT(netif, i);
#else /* #if LWIP_NETIF_HWADDRHINT */
        undiarp_cached_entry = i;
#endif /* #if LWIP_NETIF_HWADDRHINT */
        return i;
#if ARP_QUEUEING
      /* pending with queued packets? */
      } else if (arp_table[i].q != NULL) {
        if (arp_table[i].ctime >= age_queue) {
          old_queue = i;
          age_queue = arp_table[i].ctime;
        }
#endif
      /* pending without queued packets? */
      } else {
        if (arp_table[i].ctime >= age_pending) {
          old_pending = i;
          age_pending = arp_table[i].ctime;
        }
      }        
    }
    /* stable entry? */
    else if (arp_table[i].state == UNDIARP_STATE_STABLE) {
      /* if given, does IP address match IP address in ARP entry? */
      if (ipaddr && ip_addr_cmp(ipaddr, &arp_table[i].ipaddr)) {
        LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("find_entry: found matching stable entry %"U16_F"\n", (u16_t)i));
        /* found exact IP address match, simply bail out */
#if LWIP_NETIF_HWADDRHINT
        NETIF_SET_HINT(netif, i);
#else /* #if LWIP_NETIF_HWADDRHINT */
        undiarp_cached_entry = i;
#endif /* #if LWIP_NETIF_HWADDRHINT */
        return i;
      /* remember entry with oldest stable entry in oldest, its age in maxtime */
      } else if (arp_table[i].ctime >= age_stable) {
        old_stable = i;
        age_stable = arp_table[i].ctime;
      }
    }
  }
  /* { we have no match } => try to create a new entry */
   
  /* no empty entry found and not allowed to recycle? */
  if (((empty == ARP_TABLE_SIZE) && ((flags & UNDIARP_TRY_HARD) == 0))
      /* or don't create new entry, only search? */
      || ((flags & UNDIARP_FIND_ONLY) != 0)) {
    LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("find_entry: no empty entry found and not allowed to recycle\n"));
    return (s8_t)ERR_MEM;
  }
  
  /* b) choose the least destructive entry to recycle:
   * 1) empty entry
   * 2) oldest stable entry
   * 3) oldest pending entry without queued packets
   * 4) oldest pending entry with queued packets
   * 
   * { UNDIARP_TRY_HARD is set at this point }
   */ 

  /* 1) empty entry available? */
  if (empty < ARP_TABLE_SIZE) {
    i = empty;
    LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("find_entry: selecting empty entry %"U16_F"\n", (u16_t)i));
  }
  /* 2) found recyclable stable entry? */
  else if (old_stable < ARP_TABLE_SIZE) {
    /* recycle oldest stable*/
    i = old_stable;
    LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("find_entry: selecting oldest stable entry %"U16_F"\n", (u16_t)i));
#if ARP_QUEUEING
    /* no queued packets should exist on stable entries */
    LWIP_ASSERT("arp_table[i].q == NULL", arp_table[i].q == NULL);
#endif
  /* 3) found recyclable pending entry without queued packets? */
  } else if (old_pending < ARP_TABLE_SIZE) {
    /* recycle oldest pending */
    i = old_pending;
    LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("find_entry: selecting oldest pending entry %"U16_F" (without queue)\n", (u16_t)i));
#if ARP_QUEUEING
  /* 4) found recyclable pending entry with queued packets? */
  } else if (old_queue < ARP_TABLE_SIZE) {
    /* recycle oldest pending */
    i = old_queue;
    LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("find_entry: selecting oldest pending entry %"U16_F", freeing packet queue %p\n", (u16_t)i, (void *)(arp_table[i].q)));
    free_undiarp_q(arp_table[i].q);
    arp_table[i].q = NULL;
#endif
    /* no empty or recyclable entries found */
  } else {
    return (s8_t)ERR_MEM;
  }

  /* { empty or recyclable entry found } */
  LWIP_ASSERT("i < ARP_TABLE_SIZE", i < ARP_TABLE_SIZE);

  if (arp_table[i].state != UNDIARP_STATE_EMPTY)
  {
    snmp_delete_arpidx_tree(arp_table[i].netif, &arp_table[i].ipaddr);
  }
  /* recycle entry (no-op for an already empty entry) */
  arp_table[i].state = UNDIARP_STATE_EMPTY;

  /* IP address given? */
  if (ipaddr != NULL) {
    /* set IP address */
    ip_addr_set(&arp_table[i].ipaddr, ipaddr);
  }
  arp_table[i].ctime = 0;
#if LWIP_NETIF_HWADDRHINT
  NETIF_SET_HINT(netif, i);
#else /* #if LWIP_NETIF_HWADDRHINT */
  undiarp_cached_entry = i;
#endif /* #if LWIP_NETIF_HWADDRHINT */
  return (err_t)i;
}


/**
 * Send an ARP request for the given IP address and/or queue a packet.
 *
 * If the IP address was not yet in the cache, a pending ARP cache entry
 * is added and an ARP request is sent for the given address. The packet
 * is queued on this entry.
 *
 * If the IP address was already pending in the cache, a new ARP request
 * is sent for the given address. The packet is queued on this entry.
 *
 * If the IP address was already stable in the cache, and a packet is
 * given, it is directly sent and no ARP request is sent out. 
 * 
 * If the IP address was already stable in the cache, and no packet is
 * given, an ARP request is sent out.
 * 
 * @param netif The lwIP network interface on which ipaddr
 * must be queried for.
 * @param ipaddr The IP address to be resolved.
 * @param q If non-NULL, a pbuf that must be delivered to the IP address.
 * q is not freed by this function.
 *
 * @note q must only be ONE packet, not a packet queue!
 *
 * @return
 * - ERR_BUF Could not make room for Ethernet header.
 * - ERR_MEM Hardware address unknown, and no more ARP entries available
 *   to query for address or queue the packet.
 * - ERR_MEM Could not queue packet due to memory shortage.
 * - ERR_RTE No route to destination (no gateway to external networks).
 * - ERR_ARG Non-unicast address given, those will not appear in ARP cache.
 *
 */
static err_t
undiarp_query(struct netif *netif, struct ip_addr *ipaddr, struct pbuf *q)
{
  err_t result = ERR_MEM;
  s8_t i; /* ARP entry index */

  /* non-unicast address? */
  if (ip_addr_isbroadcast(ipaddr, netif) ||
      ip_addr_ismulticast(ipaddr) ||
      ip_addr_isany(ipaddr)) {
    LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiarp_query: will not add non-unicast IP address to ARP cache\n"));
    return ERR_ARG;
  }

  /* find entry in ARP cache, ask to create entry if queueing packet */
#if LWIP_NETIF_HWADDRHINT
  i = find_entry(ipaddr, UNDIARP_TRY_HARD, netif);
#else /* LWIP_NETIF_HWADDRHINT */
  i = find_entry(ipaddr, UNDIARP_TRY_HARD);
#endif /* LWIP_NETIF_HWADDRHINT */

  /* could not find or create entry? */
  if (i < 0) {
    LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiarp_query: could not create ARP entry\n"));
    if (q) {
      LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiarp_query: packet dropped\n"));
      ETHARP_STATS_INC(etharp.memerr);
    }
    return (err_t)i;
  }

  /* mark a fresh entry as pending (we just sent a request) */
  if (arp_table[i].state == UNDIARP_STATE_EMPTY) {
    arp_table[i].state = UNDIARP_STATE_PENDING;
  }

  /* { i is either a STABLE or (new or existing) PENDING entry } */
  LWIP_ASSERT("arp_table[i].state == PENDING or STABLE",
  ((arp_table[i].state == UNDIARP_STATE_PENDING) ||
   (arp_table[i].state == UNDIARP_STATE_STABLE)));

  /* do we have a pending entry? or an implicit query request? */
  if ((arp_table[i].state == UNDIARP_STATE_PENDING) || (q == NULL)) {
    /* try to resolve it; send out ARP request */
    result = undiarp_request(netif, ipaddr);
    if (result != ERR_OK) {
      /* ARP request couldn't be sent */
      /* We don't re-send arp request in undiarp_tmr, but we still queue packets,
         since this failure could be temporary, and the next packet calling
         etharp_query again could lead to sending the queued packets. */
    }
  }
  
  /* packet given? */
  if (q != NULL) {
    /* stable entry? */
    if (arp_table[i].state == UNDIARP_STATE_STABLE) {
      /* we have a valid IP->hardware address mapping */
      /* send the packet */
      result = undi_send_ip(netif, q, &(arp_table[i].hwaddr));
    /* pending entry? (either just created or already pending */
    } else if (arp_table[i].state == UNDIARP_STATE_PENDING) {
#if ARP_QUEUEING /* queue the given q packet */
      struct pbuf *p;
      int copy_needed = 0;
      /* IF q includes a PBUF_REF, PBUF_POOL or PBUF_RAM, we have no choice but
       * to copy the whole queue into a new PBUF_RAM (see bug #11400) 
       * PBUF_ROMs can be left as they are, since ROM must not get changed. */
      p = q;
      while (p) {
        LWIP_ASSERT("no packet queues allowed!", (p->len != p->tot_len) || (p->next == 0));
        if(p->type != PBUF_ROM) {
          copy_needed = 1;
          break;
        }
        p = p->next;
      }
      if(copy_needed) {
        /* copy the whole packet into new pbufs */
        p = pbuf_alloc(PBUF_RAW, p->tot_len, PBUF_RAM);
        if(p != NULL) {
          if (pbuf_copy(p, q) != ERR_OK) {
            pbuf_free(p);
            p = NULL;
          }
        }
      } else {
        /* referencing the old pbuf is enough */
        p = q;
        pbuf_ref(p);
      }
      /* packet could be taken over? */
      if (p != NULL) {
        /* queue packet ... */
        struct etharp_q_entry *new_entry;
        /* allocate a new arp queue entry */
        new_entry = memp_malloc(MEMP_ARP_QUEUE);
        if (new_entry != NULL) {
          new_entry->next = 0;
          new_entry->p = p;
          if(arp_table[i].q != NULL) {
            /* queue was already existent, append the new entry to the end */
            struct etharp_q_entry *r;
            r = arp_table[i].q;
            while (r->next != NULL) {
              r = r->next;
            }
            r->next = new_entry;
          } else {
            /* queue did not exist, first item in queue */
            arp_table[i].q = new_entry;
          }
          LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiarp_query: queued packet %p on ARP entry %"S16_F"\n", (void *)q, (s16_t)i));
          result = ERR_OK;
        } else {
          /* the pool MEMP_ARP_QUEUE is empty */
          pbuf_free(p);
          LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiarp_query: could not queue a copy of PBUF_REF packet %p (out of memory)\n", (void *)q));
          /* { result == ERR_MEM } through initialization */
        }
      } else {
        ETHARP_STATS_INC(etharp.memerr);
        LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiarp_query: could not queue a copy of PBUF_REF packet %p (out of memory)\n", (void *)q));
        /* { result == ERR_MEM } through initialization */
      }
#else /* ARP_QUEUEING == 0 */
      /* q && state == PENDING && ARP_QUEUEING == 0 => result = ERR_MEM */
      /* { result == ERR_MEM } through initialization */
      LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiarp_query: Ethernet destination address unknown, queueing disabled, packet %p dropped\n", (void *)q));
#endif
    }
  }
  return result;
}

/**
 * Resolve and fill-in address header for outgoing IP packet.
 *
 * For IP multicast and broadcast, corresponding Ethernet addresses
 * are selected and the packet is transmitted on the link.
 *
 * For unicast addresses, the packet is submitted to etharp_query(). In
 * case the IP address is outside the local network, the IP address of
 * the gateway is used.
 *
 * @param netif The lwIP network interface which the IP packet will be sent on.
 * @param q The pbuf(s) containing the IP packet to be sent.
 * @param ipaddr The IP address of the packet destination.
 *
 * @return
 * - ERR_RTE No route to destination (no gateway to external networks),
 * or the return type of either etharp_query() or etharp_send_ip().
 */
static err_t
undiarp_output(struct netif *netif, struct pbuf *q, struct ip_addr *ipaddr)
{
  static __lowmem t_PXENV_UNDI_GET_MCAST_ADDR get_mcast;
  hwaddr_t *dest;

  if (undi_is_ethernet(netif))
    return etharp_output(netif, q, ipaddr);

  /* Assume unresolved hardware address */
  dest = NULL;

  /* Determine on destination hardware address. Broadcasts and multicasts
   * are special, other IP addresses are looked up in the ARP table.
   */
  if (ip_addr_isbroadcast(ipaddr, netif)) {
    dest = NULL;
  }
  else if (ip_addr_ismulticast(ipaddr)) {
    memset(&get_mcast, 0, sizeof get_mcast);
    memcpy(&get_mcast.InetAddr, ipaddr, sizeof(get_mcast.InetAddr));
    pxe_call(PXENV_UNDI_GET_MCAST_ADDR, &get_mcast);
    dest = (hwaddr_t *)&get_mcast.MediaAddr;
  }
  else {
    /* outside local network? */
    if (!ip_addr_netcmp(ipaddr, &netif->ip_addr, &netif->netmask)) {
      /* interface has default gateway? */
      if (netif->gw.addr != 0) {
        /* send to hardware address of default gateway IP address */
        ipaddr = &(netif->gw);
      /* no default gateway available */
      } else {
        /* no route to destination error (default gateway missing) */
        return ERR_RTE;
      }
    }
    /* queue on destination Ethernet address belonging to ipaddr */
    return undiarp_query(netif, ipaddr, q);
  }
  
  /* continuation for multicast/broadcast destinations */
  /* obtain source Ethernet address of the given interface */
  /* send packet directly on the link */
  return undi_send_ip(netif, q, dest);
}

static void get_packet_fragment(t_PXENV_UNDI_ISR *isr)
{
  do {
    isr->FuncFlag = PXENV_UNDI_ISR_IN_GET_NEXT;
    pxe_call(PXENV_UNDI_ISR, &isr);
  } while (isr->FuncFlag != PXENV_UNDI_ISR_OUT_RECEIVE);
}

/**
 * Should allocate a pbuf and transfer the bytes of the incoming
 * packet from the interface into the pbuf.
 *
 * @param netif the lwip network interface structure for this undiif
 * @return a pbuf filled with the received packet (including MAC header)
 *         NULL on memory error
 */
static struct pbuf *
low_level_input(t_PXENV_UNDI_ISR *isr)
{
  struct pbuf *p, *q;
  const char *r;
  int len;

  /* Obtain the size of the packet and put it into the "len"
     variable. */
  len = isr->FrameLength;

  //printf("undiif_input, len = %d\n", len);

  /* We allocate a pbuf chain of pbufs from the pool. */
  p = pbuf_alloc(PBUF_RAW, len, PBUF_POOL);

  if (p != NULL) {
    /*
     * We iterate over the pbuf chain until we have read the entire
     * packet into the pbuf.
     */
    r = GET_PTR(isr->Frame);
    for (q = p; q != NULL; q = q->next) {
      /*
       * Read enough bytes to fill this pbuf in the chain. The
       * available data in the pbuf is given by the q->len
       * variable.
       */
      char *s = q->payload;
      int ql = q->len;

      while (ql) {
	int qb = isr->BufferLength < ql ? isr->BufferLength : ql;

	if (!qb) {
	  /*
	   * Only received a partial frame, must get the next one...
	   */
	  get_packet_fragment(isr);
	  r = GET_PTR(isr->Frame);
	} else {
	  memcpy(s, r, qb);
	  s += qb;
	  r += qb;
	  ql -= qb;
	}
      }
    }

    LINK_STATS_INC(link.recv);
  } else {
    /*
     * Dropped packet: we really should make sure we drain any partial
     * frame here...
     */
    while ((len -= isr->BufferLength) > 0)
      get_packet_fragment(isr);

    LINK_STATS_INC(link.memerr);
    LINK_STATS_INC(link.drop);
  }

  return p;
}


/**
 * Update (or insert) a IP/MAC address pair in the ARP cache.
 *
 * If a pending entry is resolved, any queued packets will be sent
 * at this point.
 * 
 * @param ipaddr IP address of the inserted ARP entry.
 * @param ethaddr Ethernet address of the inserted ARP entry.
 * @param flags Defines behaviour:
 * - ETHARP_TRY_HARD Allows ARP to insert this as a new item. If not specified,
 * only existing ARP entries will be updated.
 *
 * @return
 * - ERR_OK Succesfully updated ARP cache.
 * - ERR_MEM If we could not add a new ARP entry when ETHARP_TRY_HARD was set.
 * - ERR_ARG Non-unicast address given, those will not appear in ARP cache.
 *
 * @see pbuf_free()
 */
static err_t
update_arp_entry(struct netif *netif, struct ip_addr *ipaddr,
		 hwaddr_t *lladdr, u8_t flags)
{
  s8_t i;
  LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiif:update_arp_entry()\n"));
  LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiif:update_arp_entry: %"U16_F".%"U16_F".%"U16_F".%"U16_F" - %02"X16_F":%02"X16_F":%02"X16_F":%02"X16_F":%02"X16_F":%02"X16_F"\n",
                                        ip4_addr1(ipaddr), ip4_addr2(ipaddr), ip4_addr3(ipaddr), ip4_addr4(ipaddr), 
                                        (*lladdr)[0], (*lladdr)[1], (*lladdr)[2],
                                        (*lladdr)[3], (*lladdr)[4], (*lladdr)[5]));
  /* non-unicast address? */
  if (ip_addr_isany(ipaddr) ||
      ip_addr_isbroadcast(ipaddr, netif) ||
      ip_addr_ismulticast(ipaddr)) {
    LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiif:update_arp_entry: will not add non-unicast IP address to ARP cache\n"));
    return ERR_ARG;
  }
  /* find or create ARP entry */
#if LWIP_NETIF_HWADDRHINT
  i = find_entry(ipaddr, flags, netif);
#else /* LWIP_NETIF_HWADDRHINT */
  i = find_entry(ipaddr, flags);
#endif /* LWIP_NETIF_HWADDRHINT */
  /* bail out if no entry could be found */
  if (i < 0)
    return (err_t)i;
  
  /* mark it stable */
  arp_table[i].state = UNDIARP_STATE_STABLE;
  /* record network interface */
  arp_table[i].netif = netif;

  /* insert in SNMP ARP index tree */
  snmp_insert_arpidx_tree(netif, &arp_table[i].ipaddr);

  LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiif:update_arp_entry: updating stable entry %"S16_F"\n", (s16_t)i));
  /* update address */
  memcpy(arp_table[i].hwaddr, lladdr, netif->hwaddr_len);

  /* reset time stamp */
  arp_table[i].ctime = 0;
#if ARP_QUEUEING
  /* this is where we will send out queued packets! */
  while (arp_table[i].q != NULL) {
    struct pbuf *p;
    /* remember remainder of queue */
    struct etharp_q_entry *q = arp_table[i].q;
    /* pop first item off the queue */
    arp_table[i].q = q->next;
    /* get the packet pointer */
    p = q->p;
    /* now queue entry can be freed */
    memp_free(MEMP_ARP_QUEUE, q);
    /* send the queued IP packet */
    undi_send_ip(netif, p, lladdr);
    /* free the queued IP packet */
    pbuf_free(p);
  }
#endif
  return ERR_OK;
}

/**
 * Responds to ARP requests to us. Upon ARP replies to us, add entry to cache  
 * send out queued IP packets. Updates cache with snooped address pairs.
 *
 * Should be called for incoming ARP packets. The pbuf in the argument
 * is freed by this function.
 *
 * @param netif The lwIP network interface on which the ARP packet pbuf arrived.
 * @param ethaddr Ethernet address of netif.
 * @param p The ARP packet that arrived on netif. Is freed by this function.
 *
 * @return NULL
 *
 * @see pbuf_free()
 */
static void
undiarp_input(struct netif *netif, struct pbuf *p)
{
  struct arp_hdr *hdr;
  /* these are aligned properly, whereas the ARP header fields might not be */
  struct ip_addr sipaddr, dipaddr;
  hwaddr_t hwaddr_remote;
  u8_t *hdr_ptr;
  u8_t for_us;

  LWIP_ERROR("netif != NULL", (netif != NULL), return;);
  
  /* drop short ARP packets: we have to check for p->len instead of p->tot_len here
     since a struct arp_hdr is pointed to p->payload, so it musn't be chained! */
  if (p->len < arp_hdr_len(netif)) {
    LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE | LWIP_DBG_LEVEL_WARNING,
      ("undiarp_input: packet dropped, too short (%"S16_F"/%"S16_F")\n", p->tot_len,
      (s16_t)SIZEOF_ETHARP_PACKET));
    printf("short arp packet\n");
    ETHARP_STATS_INC(etharp.lenerr);
    ETHARP_STATS_INC(etharp.drop);
    pbuf_free(p);
    return;
  }

  hdr = p->payload;
  /* RFC 826 "Packet Reception": */
  if ((hdr->hwtype != htons(MAC_type)) ||
      (hdr->hwlen != netif->hwaddr_len) ||
      (hdr->protolen != sizeof(struct ip_addr)) ||
      (hdr->proto != htons(ETHTYPE_IP))) {
    LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE | LWIP_DBG_LEVEL_WARNING,
      ("undiarp_input: packet dropped, wrong hw type, hwlen, proto, or protolen (%"U16_F"/%"U16_F"/%"U16_F"/%"U16_F"/%"U16_F")\n",
      hdr->hwtype, hdr->hwlen, hdr->proto, hdr->protolen));
    ETHARP_STATS_INC(etharp.proterr);
    ETHARP_STATS_INC(etharp.drop);
    printf("malformed arp packet\n");
    pbuf_free(p);
    return;
  }
  ETHARP_STATS_INC(etharp.recv);

  /* Copy struct ip_addr2 to aligned ip_addr, to support compilers without
   * structure packing (not using structure copy which breaks strict-aliasing rules). */
  hdr_ptr = (unsigned char *)(hdr + 1);
  memcpy(hwaddr_remote, hdr_ptr, netif->hwaddr_len);
  hdr_ptr += netif->hwaddr_len;
  memcpy(&sipaddr, hdr_ptr, sizeof(sipaddr));
  hdr_ptr += sizeof(sipaddr);
  hdr_ptr += netif->hwaddr_len;
  memcpy(&dipaddr, hdr_ptr, sizeof(dipaddr));

  /* this interface is not configured? */
  if (netif->ip_addr.addr == 0) {
    for_us = 0;
  } else {
    /* ARP packet directed to us? */
    for_us = ip_addr_cmp(&dipaddr, &(netif->ip_addr));
  }

  /* ARP message directed to us? */
  if (for_us) {
    /* add IP address in ARP cache; assume requester wants to talk to us.
     * can result in directly sending the queued packets for this host. */
    update_arp_entry(netif, &sipaddr, &hwaddr_remote, UNDIARP_TRY_HARD);
  /* ARP message not directed to us? */
  } else {
    /* update the source IP address in the cache, if present */
    update_arp_entry(netif, &sipaddr, &hwaddr_remote, 0);
  }

  /* now act on the message itself */
  switch (htons(hdr->opcode)) {
  /* ARP request? */
  case ARP_REQUEST:
    /* ARP request. If it asked for our address, we send out a
     * reply. In any case, we time-stamp any existing ARP entry,
     * and possiby send out an IP packet that was queued on it. */

    LWIP_DEBUGF (UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiarp_input: incoming ARP request\n"));
    /* ARP request for our address? */
    if (for_us) {

      LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiarp_input: replying to ARP request for our IP address\n"));
      /* Re-use pbuf to send ARP reply.
         Since we are re-using an existing pbuf, we can't call etharp_raw since
         that would allocate a new pbuf. */
      hdr->opcode = htons(ARP_REPLY);
      hdr_ptr = (unsigned char *)(hdr + 1);
      memcpy(hdr_ptr, &netif->hwaddr, netif->hwaddr_len);
      hdr_ptr += netif->hwaddr_len;
      memcpy(hdr_ptr, &dipaddr, sizeof(dipaddr));
      hdr_ptr += sizeof(dipaddr);
      memcpy(hdr_ptr, &hwaddr_remote, netif->hwaddr_len);
      hdr_ptr += netif->hwaddr_len;
      memcpy(hdr_ptr, &sipaddr, sizeof(sipaddr));

      /* return ARP reply */
      undi_send_arp(netif, p, &hwaddr_remote);
    /* we are not configured? */
    } else if (netif->ip_addr.addr == 0) {
      /* { for_us == 0 and netif->ip_addr.addr == 0 } */
      LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiarp_input: we are unconfigured, ARP request ignored.\n"));
    /* request was not directed to us */
    } else {
      /* { for_us == 0 and netif->ip_addr.addr != 0 } */
      LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiarp_input: ARP request was not for us.\n"));
    }
    break;
  case ARP_REPLY:
    /* ARP reply. We already updated the ARP cache earlier. */
    LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiarp_input: incoming ARP reply\n"));
#if (LWIP_DHCP && DHCP_DOES_ARP_CHECK)
    /* DHCP wants to know about ARP replies from any host with an
     * IP address also offered to us by the DHCP server. We do not
     * want to take a duplicate IP address on a single network.
     * @todo How should we handle redundant (fail-over) interfaces? */
    dhcp_arp_reply(netif, &sipaddr);
#endif
    break;
  default:
    LWIP_DEBUGF(UNDIIF_ARP_DEBUG | UNDIIF_DEBUG | LWIP_DBG_TRACE, ("undiarp_input: ARP unknown opcode type %"S16_F"\n", htons(hdr->opcode)));
    ETHARP_STATS_INC(etharp.err);
    break;
  }
  /* free ARP packet */
  pbuf_free(p);
}

/**
 * This function should be called when a packet is ready to be read
 * from the interface. It uses the function low_level_input() that
 * should handle the actual reception of bytes from the network
 * interface. Then the type of the received packet is determined and
 * the appropriate input function is called.
 *
 * @param netif the lwip network interface structure for this undiif
 */
void undiif_input(t_PXENV_UNDI_ISR *isr)
{
  struct pbuf *p;
  u8_t undi_prot;
  u16_t llhdr_len;

  /* From the first isr capture the essential information */
  undi_prot = isr->ProtType;
  llhdr_len = isr->FrameHeaderLength;

  /* move received packet into a new pbuf */
  p = low_level_input(isr);
  /* no packet could be read, silently ignore this */
  if (p == NULL) return;

  if (undi_is_ethernet(&undi_netif)) {
    /* points to packet payload, which starts with an Ethernet header */
    struct eth_hdr *ethhdr = p->payload;
#if LWIP_UNDIIF_DBG(UNDIIF_ID_FULL_DEBUG)
    char *str = malloc(UNIDIF_ID_STRLEN);
    int strpos = 0;

    strpos += snprintf(str + strpos, UNIDIF_ID_STRLEN - strpos,
		       "undi recv thd '%s'\n", current()->name);
    strpos += snprintf_eth_hdr(str + strpos, UNIDIF_ID_STRLEN - strpos,
			        "undi", ethhdr, 'r', '0', "");
    strpos += snprintf_arp_hdr(str + strpos, UNIDIF_ID_STRLEN - strpos,
			        "  arp", ethhdr, 'r', '0', "");
    strpos += snprintf_ip_hdr(str + strpos, UNIDIF_ID_STRLEN - strpos,
			        "  ip", ethhdr, 'r', '0', "");
    strpos += snprintf_icmp_hdr(str + strpos, UNIDIF_ID_STRLEN - strpos,
				"    icmp", ethhdr, 'r', '0', "");
    strpos += snprintf_tcp_hdr(str + strpos, UNIDIF_ID_STRLEN - strpos,
			        "    tcp", ethhdr, 'r', '0', "");
    strpos += snprintf_udp_hdr(str + strpos, UNIDIF_ID_STRLEN - strpos,
			        "    udp", ethhdr, 'r', '0', "");
    LWIP_DEBUGF(UNDIIF_ID_FULL_DEBUG, ("%s", str));
    free(str);
#endif /* UNDIIF_ID_FULL_DEBUG */

    switch (htons(ethhdr->type)) {
    /* IP or ARP packet? */
    case ETHTYPE_IP:
    case ETHTYPE_ARP:
#if PPPOE_SUPPORT
    /* PPPoE packet? */
    case ETHTYPE_PPPOEDISC:
    case ETHTYPE_PPPOE:
#endif /* PPPOE_SUPPORT */
      /* full packet send to tcpip_thread to process */
      if (tcpip_input(p, &undi_netif)!=ERR_OK)
       { LWIP_DEBUGF(UNDIIF_NET_DEBUG | UNDIIF_DEBUG, ("undiif_input: IP input error\n"));
         pbuf_free(p);
         p = NULL;
       }
      break;

    default:
      pbuf_free(p);
      p = NULL;
      break;
    }
  } else {
    if (pbuf_header(p, -(s16_t)llhdr_len)) {
      LWIP_ASSERT("Can't move link level header in packet", 0);
      pbuf_free(p);
      p = NULL;
    } else {
      switch(undi_prot) {
      case P_IP:
        /* pass to IP layer */
        tcpip_input(p, &undi_netif);
        break;
      
      case P_ARP:
        /* pass p to ARP module */
        undiarp_input(&undi_netif, p);
        break;

      default:
        ETHARP_STATS_INC(etharp.proterr);
        ETHARP_STATS_INC(etharp.drop);
        pbuf_free(p);
        p = NULL;
        break;
      }
    }
  }
}

/**
 * Should be called at the beginning of the program to set up the
 * network interface. It calls the function low_level_init() to do the
 * actual setup of the hardware.
 *
 * This function should be passed as a parameter to netif_add().
 *
 * @param netif the lwip network interface structure for this undiif
 * @return ERR_OK if the loopif is initialized
 *         ERR_MEM if private data couldn't be allocated
 *         any other err_t on error
 */
static err_t
undiif_init(struct netif *netif)
{
  LWIP_ASSERT("netif != NULL", (netif != NULL));
#if LWIP_NETIF_HOSTNAME
  /* Initialize interface hostname */
  netif->hostname = "undi";
#endif /* LWIP_NETIF_HOSTNAME */

  /*
   * Initialize the snmp variables and counters inside the struct netif.
   * The last argument should be replaced with your link speed, in units
   * of bits per second.
   */
  NETIF_INIT_SNMP(netif, snmp_ifType_ethernet_csmacd, LINK_SPEED_OF_YOUR_NETIF_IN_BPS);

  netif->state   = NULL;	/* Private pointer if we need it */
  netif->name[0] = IFNAME0;
  netif->name[1] = IFNAME1;
  netif->output = undiarp_output;
  netif->linkoutput = undi_send_unknown;

  /* initialize the hardware */
  low_level_init(netif);

  return ERR_OK;
}

int undiif_start(uint32_t ip, uint32_t netmask, uint32_t gw)
{
  err_t err;

  // This should be done *after* the threading system and receive thread
  // have both been started.
  dprintf("undi_netif: ip %d.%d.%d.%d netmask %d.%d.%d.%d gw %d.%d.%d.%d\n",
	 ((uint8_t *)&ip)[0],
	 ((uint8_t *)&ip)[1],
	 ((uint8_t *)&ip)[2],
	 ((uint8_t *)&ip)[3],
	 ((uint8_t *)&netmask)[0],
	 ((uint8_t *)&netmask)[1],
	 ((uint8_t *)&netmask)[2],
	 ((uint8_t *)&netmask)[3],
	 ((uint8_t *)&gw)[0],
	 ((uint8_t *)&gw)[1],
	 ((uint8_t *)&gw)[2],
	 ((uint8_t *)&gw)[3]);
  err = netifapi_netif_add(&undi_netif,
    (struct ip_addr *)&ip, (struct ip_addr *)&netmask, (struct ip_addr *)&gw,
    NULL, undiif_init, tcpip_input);
  if (err)
    return err;

  netif_set_up(&undi_netif);
  netif_set_default(&undi_netif); /* Make this interface the default route */

  return ERR_OK;
}
