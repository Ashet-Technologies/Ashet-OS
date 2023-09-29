#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <console.h>
#include <netinet/in.h>
#include <com32.h>
#include <syslinux/pxe.h>

static inline uint32_t dns_resolve(const char *hostname)
{
    return pxe_dns(hostname);
}

static inline void usage(const char *s)
{
    fprintf(stderr, "Usage: %s hostname [, hostname_1, hostname_2, ...]\n", s);
}

int main(int argc, char *argv[])
{
    int i;
    uint32_t ip;

    openconsole(&dev_null_r, &dev_stdcon_w);

    if (argc < 2) {
        usage(argv[0]);
        return 1;
    }

    for (i = 1; i < argc; i++) {
        ip = dns_resolve(argv[i]);
        if (!ip) {
            printf("%s not found.\n", argv[i]);
        } else {
            printf("%-39s %08X %u.%u.%u.%u\n", argv[i], ntohl(ip), ip & 0xFF,
                   (ip >> 8) & 0xFF, (ip >> 16) & 0xFF, (ip >> 24) & 0xFF);
        }
    }

    return 0;
}
