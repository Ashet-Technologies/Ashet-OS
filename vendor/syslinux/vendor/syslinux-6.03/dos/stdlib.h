#ifndef STDLIB_H
#define STDLIB_H

typedef int ssize_t;
/* size_t is defined elsewhere */
#if __SIZEOF_POINTER__ == 4
typedef unsigned int size_t;
#elif __SIZEOF_POINTER__ == 8
typedef unsigned long size_t;
#else
#error "unsupported architecture"
#endif

void __attribute__ ((noreturn)) exit(int);

void *malloc(size_t);
void *calloc(size_t, size_t);
void free(void *);

extern unsigned long int strtoul(const char *nptr,
                                  char **endptr, int base);

#endif
