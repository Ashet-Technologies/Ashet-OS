/**
 * mangle_name:
 *
 * Mangle a filename pointed to by src into a buffer pointed
 * to by dst; ends on encountering any whitespace.
 * dst is preserved.
 *
 * This verifies that a filename is < FILENAME_MAX characters,
 * doesn't contain whitespace, zero-pads the output buffer,
 * and removes redundant slashes.
 *
 */

#include <string.h>
#include "fs.h"

void generic_mangle_name(char *dst, const char *src)
{
    char *p = dst;
    int i = FILENAME_MAX-1;

    while (not_whitespace(*src)) {
        if (*src == '/') {
            if (src[1] == '/') {
                src++;
                i--;
                continue;
            }
        }
        i--;
        *dst++ = *src++;
    }

    while (1) {
        if (dst == p)
            break;
        if (dst[-1] != '/')
            break;
	if ((dst[-1] == '/') && ((dst - 1) == p))
	    break;

        dst--;
        i++;
    }

    i++;
    for (; i > 0; i --)
        *dst++ = '\0';
}
