#include <stddef.h>
#include <com32.h>
#include <core.h>
#include <stdio.h>
#include <string.h>

void myputchar(int c)
{
    if (c == '\n')
	myputchar('\r');

    writechr(c);
}

void myputs(const char *str)
{
    while (*str)
	myputchar(*str++);
}
