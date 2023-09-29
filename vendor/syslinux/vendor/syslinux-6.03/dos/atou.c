#include "mystuff.h"

unsigned int atou(const char *s)
{
    unsigned int i = 0;
    while (isdigit(*s))
	i = i * 10 + (*s++ - '0');
    return i;
}
