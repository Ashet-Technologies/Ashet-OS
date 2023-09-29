#ifndef CTYPE_H
#define CTYPE_H

/*
 * Small subset of <ctype.h> for parsing uses, only handles ASCII
 * and passes the rest through.
 */

static inline int toupper(int c)
{
    if (c >= 'a' && c <= 'z')
	c -= 0x20;

    return c;
}

static inline int tolower(int c)
{
    if (c >= 'A' && c <= 'Z')
	c += 0x20;

    return c;
}

static inline int isspace(int ch)
{
    int space = 0;
    if ((ch == ' ') ||
	(ch == '\f') ||
	(ch == '\n') ||
	(ch == '\r') ||
	(ch == '\t') ||
	(ch == '\v'))
	space = 1;
    return space;
}

#endif /* CTYPE_H */
