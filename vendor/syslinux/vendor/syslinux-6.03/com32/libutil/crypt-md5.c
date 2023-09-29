/*-
 * Copyright (c) 2003 Poul-Henning Kamp
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <inttypes.h>
#include <md5.h>
#include <string.h>

/*
 * UNIX password
 */

static char *_crypt_to64(char *s, uint32_t v, int n)
{
    static const char itoa64[64] = "./0123456789"
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

    while (--n >= 0) {
	*s++ = itoa64[v & 0x3f];
	v >>= 6;
    }
    return s;
}

char *crypt_md5(const char *pw, const char *salt)
{
    MD5_CTX ctx, ctx1;
    unsigned long l;
    int sl, pl;
    uint32_t i;
    uint8_t final[MD5_SIZE];
    const char *sp;
    static char passwd[120];	/* Output buffer */
    static const char magic[] = "$1$";
    char *p;
    const int magic_len = sizeof magic - 1;
    int pwlen = strlen(pw);

    /* Refine the Salt first */
    sp = salt;

    /* If it starts with the magic string, then skip that */
    if (!strncmp(sp, magic, magic_len))
	sp += magic_len;

    /* Compute the salt length:
       it stops at the first '$', max 8 chars */
    for (sl = 0; sl < 8 && sp[sl] && sp[sl] != '$'; sl++) ;

    MD5Init(&ctx);

    /* The password first, since that is what is most unknown */
    MD5Update(&ctx, pw, pwlen);

    /* Then our magic string */
    MD5Update(&ctx, magic, magic_len);

    /* Then the raw salt */
    MD5Update(&ctx, sp, sl);

    /* Then just as many characters of the MD5(pw,salt,pw) */
    MD5Init(&ctx1);
    MD5Update(&ctx1, pw, pwlen);
    MD5Update(&ctx1, sp, sl);
    MD5Update(&ctx1, pw, pwlen);
    MD5Final(final, &ctx1);
    for (pl = pwlen; pl > 0; pl -= MD5_SIZE)
	MD5Update(&ctx, final, pl > MD5_SIZE ? MD5_SIZE : pl);

    /* Don't leave anything around in vm they could use. */
    memset(final, 0, sizeof final);

    /* Then something really weird... */
    for (i = pwlen; i; i >>= 1)
	if (i & 1)
	    MD5Update(&ctx, final, 1);
	else
	    MD5Update(&ctx, pw, 1);

    /* Now make the output string */
    p = passwd;

    memcpy(p, magic, magic_len);
    p += magic_len;

    memcpy(p, sp, sl);
    p += sl;

    *p++ = '$';

    MD5Final(final, &ctx);

    /*
     * and now, just to make sure things don't run too fast
     * On a 60 Mhz Pentium this takes 34 msec, so you would
     * need 30 seconds to build a 1000 entry dictionary...
     */
    for (i = 0; i < 1000; i++) {
	MD5Init(&ctx1);
	if (i & 1)
	    MD5Update(&ctx1, pw, pwlen);
	else
	    MD5Update(&ctx1, final, MD5_SIZE);

	if (i % 3)
	    MD5Update(&ctx1, sp, sl);

	if (i % 7)
	    MD5Update(&ctx1, pw, pwlen);

	if (i & 1)
	    MD5Update(&ctx1, final, MD5_SIZE);
	else
	    MD5Update(&ctx1, pw, pwlen);
	MD5Final(final, &ctx1);
    }

    l = (final[0] << 16) | (final[6] << 8) | final[12];
    p = _crypt_to64(p, l, 4);
    l = (final[1] << 16) | (final[7] << 8) | final[13];
    p = _crypt_to64(p, l, 4);
    l = (final[2] << 16) | (final[8] << 8) | final[14];
    p = _crypt_to64(p, l, 4);
    l = (final[3] << 16) | (final[9] << 8) | final[15];
    p = _crypt_to64(p, l, 4);
    l = (final[4] << 16) | (final[10] << 8) | final[5];
    p = _crypt_to64(p, l, 4);
    l = final[11];
    p = _crypt_to64(p, l, 2);
    *p = '\0';

    /* Don't leave anything around in vm they could use. */
    memset(final, 0, sizeof final);

    return passwd;
}

#ifdef TEST
#include <stdio.h>

int main(int argc, char *argv[])
{
    int i;

    for (i = 2; i < argc; i += 2) {
	puts(crypt_md5(argv[i], argv[i - 1]));
    }
    return 0;
}

#endif
