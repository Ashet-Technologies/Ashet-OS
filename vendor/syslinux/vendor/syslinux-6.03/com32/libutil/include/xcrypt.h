#ifndef _LIBUTIL_XCRYPT_H
#define _LIBUTIL_XCRYPT_H

/* Extended crypt() implementations */

char *crypt_md5(const char *, const char *);
char *sha256_crypt(const char *, const char *);
char *sha512_crypt(const char *, const char *);

#endif
