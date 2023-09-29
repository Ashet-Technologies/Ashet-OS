/*
 * Output a base64 string.
 *
 * Options include:
 * - Character 62 and 63;
 * - To pad or not to pad.
 */

#include <inttypes.h>
#include <base64.h>

size_t genbase64(char *output, const void *input, size_t size, int flags)
{
    static char charz[] =
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+_";
    uint8_t buf[3];
    int j;
    const uint8_t *p;
    char *q;
    uint32_t bv;
    int left = size;

    charz[62] = (char)flags;
    charz[63] = (char)(flags >> 8);

    p = input;
    q = output;

    while (left > 0) {
	if (left < 3) {
	    buf[0] = p[0];
	    buf[1] = (left > 1) ? p[1] : 0;
	    buf[2] = 0;
	    p = buf;
	}

	bv = (p[0] << 16) | (p[1] << 8) | p[2];
	p += 3;
	left -= 3;

	for (j = 0; j < 4; j++) {
	    *q++ = charz[(bv >> 18) & 0x3f];
	    bv <<= 6;
	}
    }

    switch (left) {
    case -1:
	if (flags & BASE64_PAD)
	    q[-1] = '=';
	else
	    q--;
	break;

    case -2:
	if (flags & BASE64_PAD)
	    q[-2] = q[-1] = '=';
	else
	    q -= 2;
	break;

    default:
	break;
    }

    *q = '\0';

    return q - output;
}

#ifdef TEST

#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[])
{
    int i;
    char buf[4096];
    int len, bytes;

    for (i = 1; i < argc; i++) {
	printf("Original: \"%s\"\n", argv[i]);

	len = strlen(argv[i]);
	bytes = genbase64(buf, argv[i], len, BASE64_MIME | BASE64_PAD);
	printf("    MIME: \"%s\" (%d)\n", buf, bytes);
	bytes = genbase64(buf, argv[i], len, BASE64_SAFE);
	printf("    Safe: \"%s\" (%d)\n", buf, bytes);
    }

    return 0;
}

#endif
