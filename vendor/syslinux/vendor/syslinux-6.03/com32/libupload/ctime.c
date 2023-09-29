#include <com32.h>
#include <string.h>
#include "ctime.h"

static uint8_t frombcd(uint8_t v)
{
    uint8_t a = v & 0x0f;
    uint8_t b = v >> 4;

    return a + b*10;
}

uint32_t posix_time(void)
{
    /* Days from March 1 for a specific month, starting in March */
    static const unsigned int yday[12] =
	{ 0, 31, 61, 92, 122, 153, 184, 214, 245, 275, 306, 337 };
    com32sys_t ir, d0, d1, t0;
    unsigned int c, y, mo, d, h, m, s;
    uint32_t t;

    memset(&ir, 0, sizeof ir);

    ir.eax.b[1] = 0x04;
    __intcall(0x1A, &ir, &d0);

    memset(&ir, 0, sizeof ir);
    ir.eax.b[1] = 0x02;
    __intcall(0x1A, &ir, &t0);

    memset(&ir, 0, sizeof ir);
    ir.eax.b[1] = 0x04;
    __intcall(0x1A, &ir, &d1);

    if (t0.ecx.b[1] < 0x12)
	d0 = d1;

    c  = frombcd(d0.ecx.b[1]);
    y  = frombcd(d0.ecx.b[0]);
    mo = frombcd(d0.edx.b[1]);
    d  = frombcd(d0.edx.b[0]);

    h  = frombcd(t0.ecx.b[1]);
    m  = frombcd(t0.ecx.b[0]);
    s  = frombcd(t0.edx.b[1]);

    /* We of course have no idea about the timezone, so ignore it */

    /*
     * Look for impossible dates... this code was written in 2010, so
     * assume any century less than 20 is just broken.
     */
    if (c < 20)
	c = 20;
    y += c*100;

    /* Consider Jan and Feb as the last months of the previous year */
    if (mo < 3) {
	y--;
	mo += 12;
    }

    /*
     * Just in case: if the month is nonsense, don't read off the end
     * of the table...
     */
    if (mo-3 > 11)
	return 0;

    t = y*365 + y/4 - y/100 + y/400 + yday[mo-3] + d - 719469;
    t *= 24;
    t += h;
    t *= 60;
    t += m;
    t *= 60;
    t += s;

    return t;
}
