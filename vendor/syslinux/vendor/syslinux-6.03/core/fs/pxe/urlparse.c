/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009-2011 Intel Corporation; author: H. Peter Anvin
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * ----------------------------------------------------------------------- */

/*
 * urlparse.c
 */

#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include "url.h"

/*
 * Return the type of a URL without modifying the string
 */
enum url_type url_type(const char *url)
{
    const char *q;

    q = strchr(url, ':');
    if (!q)
	return URL_SUFFIX;

    if (q[1] == '/' && q[2] == '/')
	return URL_NORMAL;

    if (q[1] == ':')
	return URL_OLD_TFTP;

    return URL_SUFFIX;
}

/*
 * Decompose a URL into its components.  This is done in-place;
 * this routine does not allocate any additional storage.  Freeing the
 * original buffer frees all storage used.
 */
void parse_url(struct url_info *ui, char *url)
{
    char *p = url;
    char *q, *r, *s;
    int c;

    memset(ui, 0, sizeof *ui);

    q = strchr(p, ':');
    if (q && (q[1] == '/' && q[2] == '/')) {
	ui->type = URL_NORMAL;
	
	ui->scheme = p;
	*q = '\0';
	p = q+3;
	
	q = strchr(p, '/');
	if (q) {
	    *q = '\0';
	    ui->path = q+1;
	    q = strchr(q+1, '#');
	    if (q)
		*q = '\0';
	} else {
	    ui->path = "";
	}
	
	r = strchr(p, '@');
	if (r) {
	    ui->user = p;
	    *r = '\0';
	    s = strchr(p, ':');
	    if (s) {
		*s = '\0';
		ui->passwd = s+1;
	    }
	    p = r+1;
	}
	
	ui->host = p;
	r = strchr(p, ':');
	if (r) {
	    *r++ = '\0';
	    ui->port = 0;
	    while ((c = *r++)) {
		c -= '0';
		if (c > 9)
		    break;
		ui->port = ui->port * 10 + c;
	    }
	}
    } else if (q && q[1] == ':') {
	*q = '\0';
	ui->scheme = "tftp";
	ui->host = p;
	ui->path = q+2;
	ui->type = URL_OLD_TFTP;
    } else {
	ui->path = p;
	ui->type = URL_SUFFIX;
    }
}

/*
 * Escapes unsafe characters in a URL.
 * This does *not* escape things like query characters!
 * Returns the number of characters in the total output.
 */
size_t url_escape_unsafe(char *output, const char *input, size_t bufsize)
{
    static const char uchexchar[] = "0123456789ABCDEF";
    const char *p;
    unsigned char c;
    char *q;
    size_t n = 0;

    q = output;
    for (p = input; (c = *p); p++) {
	if (c <= ' ' || c > '~') {
	    if (++n < bufsize) *q++ = '%';
	    if (++n < bufsize) *q++ = uchexchar[c >> 4];
	    if (++n < bufsize) *q++ = uchexchar[c & 15];
	} else {
	    if (++n < bufsize) *q++ = c;
	}
    }

    *q = '\0';
    return n;
}

static int hexdigit(char c)
{
    if (c >= '0' && c <= '9')
	return c - '0';
    c |= 0x20;
    if (c >= 'a' && c <= 'f')
	return c - 'a' + 10;
    return -1;
}

/*
 * Unescapes a buffer, optionally ending at an *unescaped* terminator
 * (like ; for TFTP).  The unescaping is done in-place.
 *
 * If a terminator is reached, return a pointer to the first character
 * after the terminator.
 */
char *url_unescape(char *buffer, char terminator)
{
    char *p = buffer;
    char *q = buffer;
    unsigned char c;
    int x, y;

    while ((c = *p)) {
	if (c == terminator) {
	    *q = '\0';
	    return p;
	}
	p++;
	if (c == '%') {
	    x = hexdigit(p[0]);
	    if (x >= 0) {
		y = hexdigit(p[1]);
		if (y >= 0) {
		    *q++ = (x << 4) + y;
		    p += 2;
		    continue;
		}
	    }
	}
	*q++ = c;
    }
    *q = '\0';
    return NULL;
}

#ifdef URL_TEST

int main(int argc, char *argv[])
{
    int i;
    struct url_info url;

    for (i = 1; i < argc; i++) {
	parse_url(&url, argv[i]);
	printf("scheme:  %s\n"
	       "user:    %s\n"
	       "passwd:  %s\n"
	       "host:    %s\n"
	       "port:    %d\n"
	       "path:    %s\n"
	       "type:    %d\n",
	       url.scheme, url.user, url.passwd, url.host, url.port,
	       url.path, url.type);
    }

    return 0;
}

#endif
