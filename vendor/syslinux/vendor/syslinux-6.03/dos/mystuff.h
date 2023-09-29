#ifndef MYSTUFF_H
#define MYSTUFF_H

#include <inttypes.h>
#include <stddef.h>

unsigned int skip_atou(const char **s);
unsigned int atou(const char *s);

static inline int isdigit(int ch)
{
    return (ch >= '0') && (ch <= '9');
}

struct diskio {
    uint32_t startsector;
    uint16_t sectors;
    uint16_t bufoffs, bufseg;
} __attribute__ ((packed));
int int25_read_sector(unsigned char drive, struct diskio *dio);
int int26_write_sector(unsigned char drive, struct diskio *dio);

struct psp {
    uint16_t	int20;
    uint16_t	nextpara;
    uint8_t	resv1;
    uint8_t	dispatcher[5];
    uint32_t	termvector;
    uint32_t	ctrlcvector;
    uint32_t	criterrvector;
    uint16_t	resv2[11];
    uint16_t	environment;
    uint16_t	resv3[23];
    uint8_t	fcb[2][16];
    uint32_t	resv4;
    uint8_t	cmdlen;
    char	cmdtail[127];
} __attribute__((packed));

extern struct psp _PSP;

static inline __attribute__((const))
uint16_t ds(void)
{
    uint16_t v;
    asm("movw %%ds,%0":"=rm"(v));
    return v;
}

static inline void set_fs(uint16_t seg)
{
    asm volatile("movw %0,%%fs"::"rm" (seg));
}

static inline uint8_t get_8_fs(size_t offs)
{
    uint8_t v;
    asm volatile("movb %%fs:%1,%0"
		 : "=q" (v) : "m" (*(const uint8_t *)offs));
    return v;
}

static inline uint16_t get_16_fs(size_t offs)
{
    uint16_t v;
    asm volatile("movw %%fs:%1,%0"
		 : "=r" (v) : "m" (*(const uint16_t *)offs));
    return v;
}

static inline uint32_t get_32_fs(size_t offs)
{
    uint32_t v;
    asm volatile("movl %%fs:%1,%0"
		 : "=r" (v) : "m" (*(const uint32_t *)offs));
    return v;
}

#endif /* MYSTUFF_H */
