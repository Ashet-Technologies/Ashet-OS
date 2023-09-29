#include <stdio.h>
#include <string.h>
#include <core.h>
#include "pxe.h"
#include "lwip/api.h"
#include "lwip/dns.h"

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


uint32_t dns_server[DNS_MAX_SERVERS] = {0, };

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
 * Actual resolver function.
 *
 * Points to a null-terminated in _name_ and returns the ip addr in
 * _ip_ if it exists and can be found.  If _ip_ = 0 on exit, the
 * lookup failed. _name_ will be updated
 */
__export uint32_t dns_resolv(const char *name)
{
    err_t err;
    struct ip_addr ip;
    char fullname[512];

    /*
     * Return failure on an empty input... this can happen during
     * some types of URL parsing, and this is the easiest place to
     * check for it.
     */
    if (!name || !*name)
	return 0;

    /* If it is a valid dot quad, just return that value */
    if (parse_dotquad(name, &ip.addr))
	return ip.addr;

    /* Make sure we have at least one valid DNS server */
    if (!dns_getserver(0).addr)
	return 0;

    /* Is it a local (unqualified) domain name? */
    if (!strchr(name, '.') && LocalDomain[0]) {
	snprintf(fullname, sizeof fullname, "%s.%s", name, LocalDomain);
	name = fullname;
    }

    err = netconn_gethostbyname(name, &ip);
    if (err)
	return 0;

    return ip.addr;
}

/*
 * the one should be called from ASM file
 */
void pm_pxe_dns_resolv(com32sys_t *regs)
{
    const char *name = MK_PTR(regs->ds, regs->esi.w[0]);

    regs->eax.l = dns_resolv(name);
}
