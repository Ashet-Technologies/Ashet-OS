#include <stdio.h>
#include <string.h>
#include <core.h>
#include <sys/cpu.h>
#include <lwip/opt.h>		/* DNS_MAX_SERVERS */
#include <dprintf.h>
#include "pxe.h"

char LocalDomain[256];

int over_load;
uint8_t uuid_type;
uint8_t uuid[16];

static void subnet_mask(const void *data, int opt_len)
{
    if (opt_len != 4)
	return;
    IPInfo.netmask = *(const uint32_t *)data;
}

static void router(const void *data, int opt_len)
{
    if (opt_len != 4)
	return;
    IPInfo.gateway = *(const uint32_t *)data;
}

static void dns_servers(const void *data, int opt_len)
{
    const uint32_t *dp = data;
    int num = 0;

    while (num < DNS_MAX_SERVERS) {
	uint32_t ip;

	if (opt_len < 4)
	    break;

	opt_len -= 4;
	ip = *dp++;
	if (ip_ok(ip))
	    dns_server[num++] = ip;
    }
    while (num < DNS_MAX_SERVERS)
	dns_server[num++] = 0;
}

static void local_domain(const void *data, int opt_len)
{
    memcpy(LocalDomain, data, opt_len);
    LocalDomain[opt_len] = 0;
}

static void vendor_encaps(const void *data, int opt_len)
{
    /* Only recognize PXELINUX options */
    parse_dhcp_options(data, opt_len, 208);
}

static void option_overload(const void *data, int opt_len)
{
    if (opt_len != 1)
	return;
    over_load = *(uint8_t *)data;
}

static void server(const void *data, int opt_len)
{
    uint32_t ip;

    if (opt_len != 4)
	return;

    if (IPInfo.serverip)
        return;

    ip = *(uint32_t *)data;
    if (ip_ok(ip))
        IPInfo.serverip = ip;
}

static void client_identifier(const void *data, int opt_len)
{
    if (opt_len > MAC_MAX || opt_len < 2 ||
        MAC_len != (opt_len >> 8) ||
        *(uint8_t *)data != MAC_type)
        return;

    opt_len --;
    MAC_len = opt_len & 0xff;
    memcpy(MAC, data+1, opt_len);
    MAC[opt_len] = 0;
}

static void bootfile_name(const void *data, int opt_len)
{
    memcpy(boot_file, data, opt_len);
    boot_file[opt_len] = 0;
}

static void uuid_client_identifier(const void *data, int opt_len)
{
    int type = *(const uint8_t *)data;
    if (opt_len != 17 || type != 0 || have_uuid)
        return;

    have_uuid = true;
    uuid_type = type;
    memcpy(uuid, data+1, 16);
}

static void pxelinux_configfile(const void *data, int opt_len)
{
    DHCPMagic |= 2;
    memcpy(ConfigName, data, opt_len);
    ConfigName[opt_len] = 0;
}

static void pxelinux_pathprefix(const void *data, int opt_len)
{
    DHCPMagic |= 4;
    memcpy(path_prefix, data, opt_len);
    path_prefix[opt_len] = 0;
}

static void pxelinux_reboottime(const void *data, int opt_len)
{
    if (opt_len != 4)
        return;

    RebootTime = ntohl(*(const uint32_t *)data);
    DHCPMagic |= 8;     /* Got reboot time */
}


struct dhcp_options {
    int opt_num;
    void (*fun)(const void *, int);
};

static const struct dhcp_options dhcp_opts[] = {
    {1,   subnet_mask},
    {3,   router},
    {6,   dns_servers},
    {15,  local_domain},
    {43,  vendor_encaps},
    {52,  option_overload},
    {54,  server},
    {61,  client_identifier},
    {67,  bootfile_name},
    {97,  uuid_client_identifier},
    {209, pxelinux_configfile},
    {210, pxelinux_pathprefix},
    {211, pxelinux_reboottime}
};

/*
 * Parse a sequence of DHCP options, pointed to by _option_;
 * -- some DHCP servers leave option fields unterminated
 * in violation of the spec.
 *
 * filter  contains the minimum value for the option to recognize
 * -- this is used to restrict parsing to PXELINUX-specific options only.
 */
void parse_dhcp_options(const void *option, int size, uint8_t opt_filter)
{
    int opt_num;
    int opt_len;
    const int opt_entries = sizeof(dhcp_opts) / sizeof(dhcp_opts[0]);
    int i = 0;
    const uint8_t *p = option;
    const struct dhcp_options *opt;

    /* The only 1-byte options are 00 and FF, neither of which matter */
    while (size >= 2) {
        opt_num = *p++;
	size--;

        if (opt_num == 0)
            continue;
        if (opt_num == 0xff)
            break;

        /* Anything else will have a length field */
        opt_len = *p++; /* c  <- option lenght */
        size -= opt_len + 1;
        if (size < 0)
            break;

	dprintf("DHCP: option %d, len %d\n", opt_num, opt_len);

	if (opt_num >= opt_filter) {
	    opt = dhcp_opts;
	    for (i = 0; i < opt_entries; i++) {
		if (opt_num == opt->opt_num) {
		    opt->fun(p, opt_len);
		    break;
		}
		opt++;
	    }
	}

        /* parse next */
        p += opt_len;
    }
}

/*
 * parse_dhcp
 *
 * Parse a DHCP packet.  This includes dealing with "overloaded"
 * option fields (see RFC 2132, section 9.3)
 *
 * This should fill in the following global variables, if the
 * information is present:
 *
 * MyIP		- client IP address
 * server_ip	- boot server IP address
 * net_mask	- network mask
 * gate_way	- default gateway router IP
 * boot_file	- boot file name
 * DNSServers	- DNS server IPs
 * LocalDomain	- Local domain name
 * MAC_len, MAC	- Client identifier, if MAC_len == 0
 *
 */
void parse_dhcp(const void *pkt, size_t pkt_len)
{
    const struct bootp_t *dhcp = (const struct bootp_t *)pkt;
    int opt_len;

    IPInfo.ipver = 4;		/* This is IPv4 only for now... */

    over_load = 0;
    if (ip_ok(dhcp->yip))
        IPInfo.myip = dhcp->yip;

    if (ip_ok(dhcp->sip))
        IPInfo.serverip = dhcp->sip;

    opt_len = (char *)dhcp + pkt_len - (char *)&dhcp->options;
    if (opt_len && (dhcp->option_magic == BOOTP_OPTION_MAGIC))
        parse_dhcp_options(&dhcp->options, opt_len, 0);

    if (over_load & 1)
        parse_dhcp_options(&dhcp->bootfile, 128, 0);
    else if (dhcp->bootfile[0])
	strcpy(boot_file, dhcp->bootfile);

    if (over_load & 2)
        parse_dhcp_options(dhcp->sname, 64, 0);
}
