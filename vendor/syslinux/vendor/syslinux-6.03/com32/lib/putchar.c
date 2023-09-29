/*
 * putchar.c
 *
 * gcc "printf decompilation" expects this to exist...
 */

#include <stdio.h>

#undef putchar

int putchar(int c)
{
    unsigned char ch = c;

    return _fwrite(&ch, 1, stdout) == 1 ? ch : EOF;
}
