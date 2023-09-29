/*
 * url.h
 */

#ifndef CORE_PXE_URL_H
#define CORE_PXE_URL_H

#include <stddef.h>
#include <stdint.h>

enum url_type {
    URL_NORMAL,			/* It is a full URL */
    URL_OLD_TFTP,		/* It's a ::-style TFTP path */
    URL_SUFFIX			/* Prepend the pathname prefix */
};

struct url_info {
    char *scheme;
    char *user;
    char *passwd;
    char *host;
    uint32_t ip;		/* Placeholder field not set by parse_url() */
    unsigned int port;
    char *path;			/* Includes query */
    enum url_type type;
};

enum url_type url_type(const char *url);
void parse_url(struct url_info *ui, char *url);
size_t url_escape_unsafe(char *output, const char *input, size_t bufsize);
char *url_unescape(char *buffer, char terminator);

#endif /* CORE_PXE_URL_H */
