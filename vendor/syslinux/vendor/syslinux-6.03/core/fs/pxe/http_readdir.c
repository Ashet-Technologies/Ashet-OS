/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2011 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include <inttypes.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include <dprintf.h>
#include "pxe.h"

enum http_readdir_state {
    st_start,			/*  0 Initial state */
    st_open,			/*  1 "<" */
    st_a,			/*  2 "<a" */
    st_attribute,		/*  3 "<a " */
    st_h,			/*  4 "<a h" */
    st_hr,			/*  5 */
    st_hre,			/*  6 */
    st_href,			/*  7 */
    st_hrefeq,			/*  8 */
    st_hrefqu,			/*  9 */
    st_badtag,			/* 10 */
    st_badtagqu,		/* 11 */
    st_badattr,			/* 12 */
    st_badattrqu,		/* 13 */
};

struct machine {
    char xchar;
    uint8_t st_xchar;
    uint8_t st_left;		/* < */
    uint8_t st_right;		/* > */
    uint8_t st_space;		/* white */
    uint8_t st_other;		/* anything else */
};

static const struct machine statemachine[] = {
    /* xchar	st_xchar	st_left		st_right	st_space	st_other */
    { 0,	0,		st_open,	st_start,	st_start,	st_start },
    { 'a',	st_a,		st_badtag,	st_start,	st_open,	st_badtag },
    { 0,	0,		st_open,	st_open,	st_attribute,	st_badtag },
    { 'h',	st_h,		st_open,	st_start,	st_attribute,	st_badattr },
    { 'r',	st_hr,		st_open,	st_start,	st_attribute,	st_badattr },
    { 'e',	st_hre,		st_open,	st_start,	st_attribute,	st_badattr },
    { 'f',	st_href,	st_open,	st_start,	st_attribute,	st_badattr },
    { '=',	st_hrefeq,	st_open,	st_start,	st_attribute,	st_badattr },
    { '\"',	st_hrefqu,	st_open,	st_start,	st_attribute,	st_hrefeq },
    { '\"',	st_attribute,	st_hrefqu,	st_hrefqu,	st_hrefqu,	st_hrefqu },
    { '\"',	st_badtagqu,	st_open,	st_start,	st_badtag,	st_badtag },
    { '\"',	st_badtag,	st_badtagqu,	st_badtagqu,	st_badtagqu,	st_badtagqu },
    { '\"',	st_badattrqu,	st_open,	st_start,	st_attribute,	st_badattr },
    { '\"',	st_attribute,	st_badattrqu,	st_badattrqu,	st_badattrqu,	st_badattrqu },
};

struct html_entity {
    uint16_t ucs;
    const char entity[9];
};

static const struct html_entity entities[] = {
    {   34, "quot" },
    {   38, "amp" },
    {   60, "lt" },
    {   62, "gt" },
#ifdef HTTP_ALL_ENTITIES
    {  160, "nbsp" },
    {  161, "iexcl" },
    {  162, "cent" },
    {  163, "pound" },
    {  164, "curren" },
    {  165, "yen" },
    {  166, "brvbar" },
    {  167, "sect" },
    {  168, "uml" },
    {  169, "copy" },
    {  170, "ordf" },
    {  171, "laquo" },
    {  172, "not" },
    {  173, "shy" },
    {  174, "reg" },
    {  175, "macr" },
    {  176, "deg" },
    {  177, "plusmn" },
    {  178, "sup2" },
    {  179, "sup3" },
    {  180, "acute" },
    {  181, "micro" },
    {  182, "para" },
    {  183, "middot" },
    {  184, "cedil" },
    {  185, "sup1" },
    {  186, "ordm" },
    {  187, "raquo" },
    {  188, "frac14" },
    {  189, "frac12" },
    {  190, "frac34" },
    {  191, "iquest" },
    {  192, "Agrave" },
    {  193, "Aacute" },
    {  194, "Acirc" },
    {  195, "Atilde" },
    {  196, "Auml" },
    {  197, "Aring" },
    {  198, "AElig" },
    {  199, "Ccedil" },
    {  200, "Egrave" },
    {  201, "Eacute" },
    {  202, "Ecirc" },
    {  203, "Euml" },
    {  204, "Igrave" },
    {  205, "Iacute" },
    {  206, "Icirc" },
    {  207, "Iuml" },
    {  208, "ETH" },
    {  209, "Ntilde" },
    {  210, "Ograve" },
    {  211, "Oacute" },
    {  212, "Ocirc" },
    {  213, "Otilde" },
    {  214, "Ouml" },
    {  215, "times" },
    {  216, "Oslash" },
    {  217, "Ugrave" },
    {  218, "Uacute" },
    {  219, "Ucirc" },
    {  220, "Uuml" },
    {  221, "Yacute" },
    {  222, "THORN" },
    {  223, "szlig" },
    {  224, "agrave" },
    {  225, "aacute" },
    {  226, "acirc" },
    {  227, "atilde" },
    {  228, "auml" },
    {  229, "aring" },
    {  230, "aelig" },
    {  231, "ccedil" },
    {  232, "egrave" },
    {  233, "eacute" },
    {  234, "ecirc" },
    {  235, "euml" },
    {  236, "igrave" },
    {  237, "iacute" },
    {  238, "icirc" },
    {  239, "iuml" },
    {  240, "eth" },
    {  241, "ntilde" },
    {  242, "ograve" },
    {  243, "oacute" },
    {  244, "ocirc" },
    {  245, "otilde" },
    {  246, "ouml" },
    {  247, "divide" },
    {  248, "oslash" },
    {  249, "ugrave" },
    {  250, "uacute" },
    {  251, "ucirc" },
    {  252, "uuml" },
    {  253, "yacute" },
    {  254, "thorn" },
    {  255, "yuml" },
    {  338, "OElig" },
    {  339, "oelig" },
    {  352, "Scaron" },
    {  353, "scaron" },
    {  376, "Yuml" },
    {  402, "fnof" },
    {  710, "circ" },
    {  732, "tilde" },
    {  913, "Alpha" },
    {  914, "Beta" },
    {  915, "Gamma" },
    {  916, "Delta" },
    {  917, "Epsilon" },
    {  918, "Zeta" },
    {  919, "Eta" },
    {  920, "Theta" },
    {  921, "Iota" },
    {  922, "Kappa" },
    {  923, "Lambda" },
    {  924, "Mu" },
    {  925, "Nu" },
    {  926, "Xi" },
    {  927, "Omicron" },
    {  928, "Pi" },
    {  929, "Rho" },
    {  931, "Sigma" },
    {  932, "Tau" },
    {  933, "Upsilon" },
    {  934, "Phi" },
    {  935, "Chi" },
    {  936, "Psi" },
    {  937, "Omega" },
    {  945, "alpha" },
    {  946, "beta" },
    {  947, "gamma" },
    {  948, "delta" },
    {  949, "epsilon" },
    {  950, "zeta" },
    {  951, "eta" },
    {  952, "theta" },
    {  953, "iota" },
    {  954, "kappa" },
    {  955, "lambda" },
    {  956, "mu" },
    {  957, "nu" },
    {  958, "xi" },
    {  959, "omicron" },
    {  960, "pi" },
    {  961, "rho" },
    {  962, "sigmaf" },
    {  963, "sigma" },
    {  964, "tau" },
    {  965, "upsilon" },
    {  966, "phi" },
    {  967, "chi" },
    {  968, "psi" },
    {  969, "omega" },
    {  977, "thetasym" },
    {  978, "upsih" },
    {  982, "piv" },
    { 8194, "ensp" },
    { 8195, "emsp" },
    { 8201, "thinsp" },
    { 8204, "zwnj" },
    { 8205, "zwj" },
    { 8206, "lrm" },
    { 8207, "rlm" },
    { 8211, "ndash" },
    { 8212, "mdash" },
    { 8216, "lsquo" },
    { 8217, "rsquo" },
    { 8218, "sbquo" },
    { 8220, "ldquo" },
    { 8221, "rdquo" },
    { 8222, "bdquo" },
    { 8224, "dagger" },
    { 8225, "Dagger" },
    { 8226, "bull" },
    { 8230, "hellip" },
    { 8240, "permil" },
    { 8242, "prime" },
    { 8243, "Prime" },
    { 8249, "lsaquo" },
    { 8250, "rsaquo" },
    { 8254, "oline" },
    { 8260, "frasl" },
    { 8364, "euro" },
    { 8465, "image" },
    { 8472, "weierp" },
    { 8476, "real" },
    { 8482, "trade" },
    { 8501, "alefsym" },
    { 8592, "larr" },
    { 8593, "uarr" },
    { 8594, "rarr" },
    { 8595, "darr" },
    { 8596, "harr" },
    { 8629, "crarr" },
    { 8656, "lArr" },
    { 8657, "uArr" },
    { 8658, "rArr" },
    { 8659, "dArr" },
    { 8660, "hArr" },
    { 8704, "forall" },
    { 8706, "part" },
    { 8707, "exist" },
    { 8709, "empty" },
    { 8711, "nabla" },
    { 8712, "isin" },
    { 8713, "notin" },
    { 8715, "ni" },
    { 8719, "prod" },
    { 8721, "sum" },
    { 8722, "minus" },
    { 8727, "lowast" },
    { 8730, "radic" },
    { 8733, "prop" },
    { 8734, "infin" },
    { 8736, "ang" },
    { 8743, "and" },
    { 8744, "or" },
    { 8745, "cap" },
    { 8746, "cup" },
    { 8747, "int" },
    { 8756, "there4" },
    { 8764, "sim" },
    { 8773, "cong" },
    { 8776, "asymp" },
    { 8800, "ne" },
    { 8801, "equiv" },
    { 8804, "le" },
    { 8805, "ge" },
    { 8834, "sub" },
    { 8835, "sup" },
    { 8836, "nsub" },
    { 8838, "sube" },
    { 8839, "supe" },
    { 8853, "oplus" },
    { 8855, "otimes" },
    { 8869, "perp" },
    { 8901, "sdot" },
    { 8968, "lceil" },
    { 8969, "rceil" },
    { 8970, "lfloor" },
    { 8971, "rfloor" },
    { 9001, "lang" },
    { 9002, "rang" },
    { 9674, "loz" },
    { 9824, "spades" },
    { 9827, "clubs" },
    { 9829, "hearts" },
    { 9830, "diams" },
#endif /* HTTP_ALL_ENTITIES */
    { 0, "" }
};

struct entity_state {
    char entity_buf[16];
    char *ep;
};

static char *emit(char *p, int c, struct entity_state *st)
{
    const struct html_entity *ent;
    unsigned int ucs;

    if (!st->ep) {
	if (c == '&') {
	    /* Entity open */
	    st->ep = st->entity_buf;
	} else {
	    *p++ = c;
	}
    } else {
	if (c == ';') {
	    st->ep = NULL;
	    *p = '\0';
	    if (st->entity_buf[0] == '#') {
		if ((st->entity_buf[1] | 0x20)== 'x') {
		    ucs = strtoul(st->entity_buf + 2, NULL, 16);
		} else {
		    ucs = strtoul(st->entity_buf + 1, NULL, 10);
		}
	    } else {
		for (ent = entities; ent->ucs; ent++) {
		    if (!strcmp(st->entity_buf, ent->entity))
			break;
		}
		ucs = ent->ucs;
	    }
	    if (ucs < 32 || ucs >= 0x10ffff)
		return p;	/* Bogus */
	    if (ucs >= 0x10000) {
		*p++ = 0xf0 + (ucs >> 18);
		*p++ = 0x80 + ((ucs >> 12) & 0x3f);
		*p++ = 0x80 + ((ucs >> 6) & 0x3f);
		*p++ = 0x80 + (ucs & 0x3f);
	    } else if (ucs >= 0x800) {
		*p++ = 0xe0 + (ucs >> 12);
		*p++ = 0x80 + ((ucs >> 6) & 0x3f);
		*p++ = 0x80 + (ucs & 0x3f);
	    } else if (ucs >= 0x80) {
		*p++ = 0xc0 + (ucs >> 6);
		*p++ = 0x80 + (ucs & 0x3f);
	    } else {
		*p++ = ucs;
	    }
	} else if (st->ep < st->entity_buf + sizeof st->entity_buf - 1) {
	    *st->ep++ = c;
	}
    }
    return p;
}

static const char *http_get_filename(struct inode *inode, char *buf)
{
    int c, lc;
    char *p;
    const struct machine *sm;
    struct entity_state es;
    enum http_readdir_state state = st_start;
    enum http_readdir_state pstate = st_start;

    memset(&es, 0, sizeof es);

    p = buf;
    for (;;) {
	c = pxe_getc(inode);
	if (c == -1)
	    return NULL;

	lc = tolower(c);

	sm = &statemachine[state];

	if (lc == sm->xchar)
	    state = sm->st_xchar;
	else if (c == '<')
	    state = sm->st_left;
	else if (c == '>')
	    state = sm->st_right;
	else if (isspace(c))
	    state = sm->st_space;
	else
	    state = sm->st_other;

	if (state == st_hrefeq || state == st_hrefqu) {
	    if (state != pstate)
		p = buf;
	    else if (p < buf + FILENAME_MAX)
		p = emit(p, c, &es);
	    pstate = state;
	} else {
	    if (pstate != st_start)
		pstate = st_start;
	    if (p != buf && state == st_start) {
		*p = '\0';
		return buf;
	    }
	}
    }
}

int http_readdir(struct inode *inode, struct dirent *dirent)
{
    char buf[FILENAME_MAX + 6];
    const char *fn, *sp;

    for (;;) {
	fn = http_get_filename(inode, buf);

	if (!fn)
	    return -1;		/* End of directory */

	/* Ignore entries with http special characters */
	if (strchr(fn, '#'))
	    continue;
	if (strchr(fn, '?'))
	    continue;

	/* A slash if present has to be the last character, and not the first */
	sp = strchr(fn, '/');
	if (sp) {
	    if (sp == fn || sp[1])
		continue;
	} else {
	    sp = strchr(fn, '\0');
	}

	if (sp > fn + NAME_MAX)
	    continue;

	dirent->d_ino = 0;	/* Not applicable */
	dirent->d_off = 0;	/* Not applicable */
	dirent->d_reclen = offsetof(struct dirent, d_name) + (sp-fn) + 1;
	dirent->d_type = *sp == '/' ? DT_DIR : DT_REG;
	memcpy(dirent->d_name, fn, sp-fn);
	dirent->d_name[sp-fn] = '\0';
	return 0;
    }
}
