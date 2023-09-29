#include <stdio.h>
#include <string.h>
#include <core.h>
#include "pxe.h"

/* DNS CLASS values we care about */
#define CLASS_IN	1

/* DNS TYPE values we care about */
#define TYPE_A		1
#define TYPE_CNAME	5

/*
 * The DNS header structure
 */
struct dnshdr {
    uint16_t id;
    uint16_t flags;
    /* number of entries in the question section */
    uint16_t qdcount;
    /* number of resource records in the answer section */
    uint16_t ancount;
    /* number of name server resource records in the authority records section*/
    uint16_t nscount;
    /* number of resource records in the additional records section */
    uint16_t arcount;
} __attribute__ ((packed));

/*
 * The DNS query structure
 */
struct dnsquery {
    uint16_t qtype;
    uint16_t qclass;
} __attribute__ ((packed));

/*
 * The DNS Resource recodes structure
 */
struct dnsrr {
    uint16_t type;
    uint16_t class;
    uint32_t ttl;
    uint16_t rdlength;   /* The lenght of this rr data */
    char     rdata[];
} __attribute__ ((packed));


#define DNS_PORT	htons(53)               /* Default DNS port */
#define DNS_MAX_SERVERS 4		/* Max no of DNS servers */

uint32_t dns_server[DNS_MAX_SERVERS] = {0, };


/*
 * Turn a string in _src_ into a DNS "label set" in _dst_; returns the
 * number of dots encountered. On return, *dst is updated.
 */
int dns_mangle(char **dst, const char *p)
{
    char *q = *dst;
    char *count_ptr;
    char c;
    int dots = 0;

    count_ptr = q;
    *q++ = 0;

    while (1) {
        c = *p++;
        if (c == 0 || c == ':' || c == '/')
            break;
        if (c == '.') {
            dots++;
            count_ptr = q;
            *q++ = 0;
            continue;
        }

        *count_ptr += 1;
        *q++ = c;
    }

    if (*count_ptr)
        *q++ = 0;

    /* update the strings */
    *dst = q;
    return dots;
}


/*
 * Compare two sets of DNS labels, in _s1_ and _s2_; the one in _s2_
 * is allowed pointers relative to a packet in buf.
 *
 */
static bool dns_compare(const void *s1, const void *s2, const void *buf)
{
    const uint8_t *q = s1;
    const uint8_t *p = s2;
    unsigned int c0, c1;

    while (1) {
	c0 = p[0];
        if (c0 >= 0xc0) {
	    /* Follow pointer */
	    c1 = p[1];
	    p = (const uint8_t *)buf + ((c0 - 0xc0) << 8) + c1;
	} else if (c0) {
	    c0++;		/* Include the length byte */
	    if (memcmp(q, p, c0))
		return false;
	    q += c0;
	    p += c0;
	} else {
	    return *q == 0;
	}
    }
}

/*
 * Copy a DNS label into a buffer, considering the possibility that we might
 * have to follow pointers relative to "buf".
 * Returns a pointer to the first free byte *after* the terminal null.
 */
static void *dns_copylabel(void *dst, const void *src, const void *buf)
{
    uint8_t *q = dst;
    const uint8_t *p = src;
    unsigned int c0, c1;

    while (1) {
	c0 = p[0];
        if (c0 >= 0xc0) {
	    /* Follow pointer */
	    c1 = p[1];
	    p = (const uint8_t *)buf + ((c0 - 0xc0) << 8) + c1;
	} else if (c0) {
	    c0++;		/* Include the length byte */
	    memcpy(q, p, c0);
	    p += c0;
	    q += c0;
	} else {
	    *q++ = 0;
	    return q;
	}
    }
}

/*
 * Skip past a DNS label set in DS:SI
 */
static char *dns_skiplabel(char *label)
{
    uint8_t c;

    while (1) {
        c = *label++;
        if (c >= 0xc0)
            return ++label; /* pointer is two bytes */
        if (c == 0)
            return label;
        label += c;
    }
}

extern const uint8_t TimeoutTable[];
extern uint16_t get_port(void);
extern void free_port(uint16_t port);

/*
 * parse the ip_str and return the ip address with *res.
 * return true if the whole string was consumed and the result
 * was valid.
 *
 */
static bool parse_dotquad(const char *ip_str, uint32_t *res)
{
    const char *p = ip_str;
    uint8_t part = 0;
    uint32_t ip = 0;
    int i;

    for (i = 0; i < 4; i++) {
        while (is_digit(*p)) {
            part = part * 10 + *p - '0';
            p++;
        }
        if (i != 3 && *p != '.')
            return false;

        ip = (ip << 8) | part;
        part = 0;
        p++;
    }
    p--;

    *res = htonl(ip);
    return *p == '\0';
}

/*
 * Actual resolver function
 * Points to a null-terminated or :-terminated string in _name_
 * and returns the ip addr in _ip_ if it exists and can be found.
 * If _ip_ = 0 on exit, the lookup failed. _name_ will be updated
 *
 * XXX: probably need some caching here.
 */
__export uint32_t dns_resolv(const char *name)
{
    static char __lowmem DNSSendBuf[PKTBUF_SIZE];
    static char __lowmem DNSRecvBuf[PKTBUF_SIZE];
    char *p;
    int err;
    int dots;
    int same;
    int rd_len;
    int ques, reps;    /* number of questions and replies */
    uint8_t timeout;
    const uint8_t *timeout_ptr = TimeoutTable;
    uint32_t oldtime;
    uint32_t srv;
    uint32_t *srv_ptr;
    struct dnshdr *hd1 = (struct dnshdr *)DNSSendBuf;
    struct dnshdr *hd2 = (struct dnshdr *)DNSRecvBuf;
    struct dnsquery *query;
    struct dnsrr *rr;
    static __lowmem struct s_PXENV_UDP_WRITE udp_write;
    static __lowmem struct s_PXENV_UDP_READ  udp_read;
    uint16_t local_port;
    uint32_t result = 0;

    /*
     * Return failure on an empty input... this can happen during
     * some types of URL parsing, and this is the easiest place to
     * check for it.
     */
    if (!name || !*name)
	return 0;

    /* If it is a valid dot quad, just return that value */
    if (parse_dotquad(name, &result))
	return result;

    /* Make sure we have at least one valid DNS server */
    if (!dns_server[0])
	return 0;

    /* Get a local port number */
    local_port = get_port();

    /* First, fill the DNS header struct */
    hd1->id++;                      /* New query ID */
    hd1->flags   = htons(0x0100);   /* Recursion requested */
    hd1->qdcount = htons(1);        /* One question */
    hd1->ancount = 0;               /* No answers */
    hd1->nscount = 0;               /* No NS */
    hd1->arcount = 0;               /* No AR */

    p = DNSSendBuf + sizeof(struct dnshdr);
    dots = dns_mangle(&p, name);   /* store the CNAME */

    if (!dots) {
        p--; /* Remove final null */
        /* Uncompressed DNS label set so it ends in null */
        p = stpcpy(p, LocalDomain);
    }

    /* Fill the DNS query packet */
    query = (struct dnsquery *)p;
    query->qtype  = htons(TYPE_A);
    query->qclass = htons(CLASS_IN);
    p += sizeof(struct dnsquery);

    /* Now send it to name server */
    timeout_ptr = TimeoutTable;
    timeout = *timeout_ptr++;
    srv_ptr = dns_server;
    while (timeout) {
	srv = *srv_ptr++;
	if (!srv) {
	    srv_ptr = dns_server;
	    srv = *srv_ptr++;
	}

        udp_write.status      = 0;
        udp_write.ip          = srv;
        udp_write.gw          = gateway(srv);
        udp_write.src_port    = local_port;
        udp_write.dst_port    = DNS_PORT;
        udp_write.buffer_size = p - DNSSendBuf;
        udp_write.buffer      = FAR_PTR(DNSSendBuf);
        err = pxe_call(PXENV_UDP_WRITE, &udp_write);
        if (err || udp_write.status)
            continue;

        oldtime = jiffies();
	do {
	    if (jiffies() - oldtime >= timeout)
		goto again;

            udp_read.status      = 0;
            udp_read.src_ip      = srv;
            udp_read.dest_ip     = IPInfo.myip;
            udp_read.s_port      = DNS_PORT;
            udp_read.d_port      = local_port;
            udp_read.buffer_size = PKTBUF_SIZE;
            udp_read.buffer      = FAR_PTR(DNSRecvBuf);
            err = pxe_call(PXENV_UDP_READ, &udp_read);
	} while (err || udp_read.status || hd2->id != hd1->id);

        if ((hd2->flags ^ 0x80) & htons(0xf80f))
            goto badness;

        ques = htons(hd2->qdcount);   /* Questions */
        reps = htons(hd2->ancount);   /* Replies   */
        p = DNSRecvBuf + sizeof(struct dnshdr);
        while (ques--) {
            p = dns_skiplabel(p); /* Skip name */
            p += 4;               /* Skip question trailer */
        }

        /* Parse the replies */
        while (reps--) {
            same = dns_compare(DNSSendBuf + sizeof(struct dnshdr),
			       p, DNSRecvBuf);
            p = dns_skiplabel(p);
            rr = (struct dnsrr *)p;
            rd_len = ntohs(rr->rdlength);
            if (same && ntohs(rr->class) == CLASS_IN) {
		switch (ntohs(rr->type)) {
		case TYPE_A:
		    if (rd_len == 4) {
			result = *(uint32_t *)rr->rdata;
			goto done;
		    }
		    break;
		case TYPE_CNAME:
		    dns_copylabel(DNSSendBuf + sizeof(struct dnshdr),
				  rr->rdata, DNSRecvBuf);
		    /*
		     * We should probably rescan the packet from the top
		     * here, and technically we might have to send a whole
		     * new request here...
		     */
		    break;
		default:
		    break;
		}
	    }

            /* not the one we want, try next */
            p += sizeof(struct dnsrr) + rd_len;
        }

    badness:
        /*
         *
         ; We got back no data from this server.
         ; Unfortunately, for a recursive, non-authoritative
         ; query there is no such thing as an NXDOMAIN reply,
         ; which technically means we can't draw any
         ; conclusions.  However, in practice that means the
         ; domain doesn't exist.  If this turns out to be a
         ; problem, we may want to add code to go through all
         ; the servers before giving up.

         ; If the DNS server wasn't capable of recursion, and
         ; isn't capable of giving us an authoritative reply
         ; (i.e. neither AA or RA set), then at least try a
         ; different setver...
        */
        if (hd2->flags == htons(0x480))
            continue;

        break; /* failed */

    again:
	continue;
    }

done:
    free_port(local_port);	/* Return port number to the free pool */

    return result;
}
