/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2008 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <string.h>
#include <xcrypt.h>
#include <sha1.h>
#include <base64.h>

#include "menu.h"

static int passwd_compare_sha1(const char *passwd, const char *entry)
{
    struct {
	SHA1_CTX ctx;
	unsigned char sha1[20], pwdsha1[20];
    } d;
    const char *p;
    int rv;

    SHA1Init(&d.ctx);

    if ((p = strchr(passwd + 3, '$'))) {
	SHA1Update(&d.ctx, (void *)passwd + 3, p - (passwd + 3));
	p++;
    } else {
	p = passwd + 3;		/* Assume no salt */
    }

    SHA1Update(&d.ctx, (void *)entry, strlen(entry));
    SHA1Final(d.sha1, &d.ctx);

    memset(d.pwdsha1, 0, 20);
    unbase64(d.pwdsha1, 20, p);

    rv = !memcmp(d.sha1, d.pwdsha1, 20);

    memset(&d, 0, sizeof d);
    return rv;
}

static int passwd_compare_md5(const char *passwd, const char *entry)
{
    const char *crypted = crypt_md5(entry, passwd + 3);
    int len = strlen(crypted);

    return !strncmp(crypted, passwd, len) &&
	(passwd[len] == '\0' || passwd[len] == '$');
}

static int passwd_compare_sha256(const char *passwd, const char *entry)
{
    const char *crypted = sha256_crypt(entry, passwd + 3);
    int len = strlen(crypted);

    return !strncmp(crypted, passwd, len) &&
	(passwd[len] == '\0' || passwd[len] == '$');
}

static int passwd_compare_sha512(const char *passwd, const char *entry)
{
    const char *crypted = sha512_crypt(entry, passwd + 3);
    int len = strlen(crypted);

    return !strncmp(crypted, passwd, len) &&
	(passwd[len] == '\0' || passwd[len] == '$');
}

int passwd_compare(const char *passwd, const char *entry)
{
    if (passwd[0] != '$' || !passwd[1] || passwd[2] != '$') {
	/* Plaintext passwd, yuck! */
	return !strcmp(entry, passwd);
    } else {
	switch (passwd[1]) {
	case '1':
	    return passwd_compare_md5(passwd, entry);
	case '4':
	    return passwd_compare_sha1(passwd, entry);
	case '5':
	    return passwd_compare_sha256(passwd, entry);
	case '6':
	    return passwd_compare_sha512(passwd, entry);
	default:
	    return 0;		/* Unknown encryption algorithm -> false */
	}
    }
}
