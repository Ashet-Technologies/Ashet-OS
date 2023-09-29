#ifndef STDIO_H
#define STDIO_H

#include <stdarg.h>
#include <stdlib.h>

typedef unsigned int off_t;

int putchar(int);
int puts(const char *);
int sprintf(char *buf, const char *fmt, ...);
int vsprintf(char *buf, const char *fmt, va_list args);
int printf(const char *fmt, ...);

#define stdin	0
#define stdout	1
#define stderr	2

#define EOF (-1)

#define fprintf(x, y, ...) printf(y, ## __VA_ARGS__)

#endif /* STDIO_H */
