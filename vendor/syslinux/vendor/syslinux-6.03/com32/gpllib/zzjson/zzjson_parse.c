/* JSON Parser
 * ZZJSON - Copyright (C) 2008-2009 by Ivo van Poorten
 * License: GNU Lesser General Public License version 2.1
 */

#include "zzjson.h"
#include <ctype.h>
#include <string.h>
#include <math.h>
#include <stdio.h>

#define GETC()          config->getchar(config->ihandle)
#define UNGETC(c)       config->ungetchar(c, config->ihandle)
#define SKIPWS()        skipws(config)
#ifdef CONFIG_NO_ERROR_MESSAGES
#define ERROR(x...)
#else
#define ERROR(x...)     config->error(config->ehandle, ##x)
#endif
#define MEMERROR()      ERROR("out of memory")

#define ALLOW_EXTRA_COMMA    (config->strictness & ZZJSON_ALLOW_EXTRA_COMMA)
#define ALLOW_ILLEGAL_ESCAPE (config->strictness & ZZJSON_ALLOW_ILLEGAL_ESCAPE)
#define ALLOW_CONTROL_CHARS  (config->strictness & ZZJSON_ALLOW_CONTROL_CHARS)
#define ALLOW_GARBAGE_AT_END (config->strictness & ZZJSON_ALLOW_GARBAGE_AT_END)
#define ALLOW_COMMENTS       (config->strictness & ZZJSON_ALLOW_COMMENTS)

static ZZJSON *parse_array(ZZJSON_CONFIG *config);
static ZZJSON *parse_object(ZZJSON_CONFIG *config);

static void skipws(ZZJSON_CONFIG *config) {
    int d, c = GETC();
morews:
    while (isspace(c)) c = GETC();
    if (!ALLOW_COMMENTS) goto endws;
    if (c != '/') goto endws;
    d = GETC();
    if (d != '*') goto endws; /* pushing back c will generate a parse error */
    c = GETC();
morecomments:
    while (c != '*') {
        if (c == EOF) goto endws;
        c = GETC();
    }
    c = GETC();
    if (c != '/') goto morecomments;
    c = GETC();
    if (isspace(c) || c == '/') goto morews;
endws:
    UNGETC(c);
}

static char *parse_string(ZZJSON_CONFIG *config) {
    unsigned int len = 16, pos = 0;
    int c;
    char *str = NULL;

    SKIPWS();
    c = GETC();
    if (c != '"') {
        ERROR("string: expected \" at the start");
        return NULL;
    }

    str = config->malloc(len);
    if (!str) {
        MEMERROR();
        return NULL;
    }
    c = GETC();
    while (c > 0 && c != '"') {
        if (!ALLOW_CONTROL_CHARS && c >= 0 && c <= 31) {
            ERROR("string: control characters not allowed");
            goto errout;
        }
        if (c == '\\') {
            c = GETC();
            switch (c) {
                case 'b': c = '\b'; break;
                case 'f': c = '\f'; break;
                case 'n': c = '\n'; break;
                case 'r': c = '\r'; break;
                case 't': c = '\t'; break;
                case 'u': {
                    UNGETC(c);    /* ignore \uHHHH, copy verbatim */
                    c = '\\';
                    break;
                }
                case '\\': case '/': case '"':
                          break;
                default:
                    if (!ALLOW_ILLEGAL_ESCAPE) {
                        ERROR("string: illegal escape character");
                        goto errout;
                    }
            }
        }
        str[pos++] = c;
        if (pos == len-1) {
            void *tmp = str;
            len *= 2;
            str = config->realloc(str, len);
            if (!str) {
                MEMERROR();
                str = tmp;
                goto errout;
            }
        }
        c = GETC();
    }
    if (c != '"') {
        ERROR("string: expected \" at the end");
        goto errout;
    }
    str[pos] = 0;
    return str;

errout:
    config->free(str);
    return NULL;
}

static ZZJSON *parse_string2(ZZJSON_CONFIG *config) {
    ZZJSON *zzjson = NULL;
    char *str;

    str = parse_string(config);
    if (str) {
        zzjson = config->calloc(1, sizeof(ZZJSON));
        if (!zzjson) {
            MEMERROR();
            config->free(str);
            return NULL;
        }
        zzjson->type = ZZJSON_STRING;
        zzjson->value.string.string = str;
    }
    return zzjson;
}

static ZZJSON *parse_number(ZZJSON_CONFIG *config) {
    ZZJSON *zzjson;
    unsigned long long ival = 0, expo = 0;
    double dval = 0.0, frac = 0.0, fracshft = 10.0;
    int c, dbl = 0, sign = 1, signexpo = 1;

    SKIPWS();
    c = GETC();
    if (c == '-') {
        sign = -1;
        c = GETC();
    }
    if (c == '0') {
        c = GETC();
        goto skip;
    }

    if (!isdigit(c)) {
        ERROR("number: digit expected");
        return NULL;
    }

    while (isdigit(c)) {
        ival *= 10;
        ival += c - '0';
        c = GETC();
    }

skip:
    if (c != '.') goto skipfrac;

    dbl = 1;

    c = GETC();
    if (!isdigit(c)) {
        ERROR("number: digit expected");
        return NULL;
    }

    while (isdigit(c)) {
        frac += (double)(c - '0') / fracshft;
        fracshft *= 10.0;
        c = GETC();
    }

skipfrac:
    if (c != 'e' && c != 'E') goto skipexpo;

    dbl = 1;

    c = GETC();
    if (c == '+')
        c = GETC();
    else if (c == '-') {
        signexpo = -1;
        c = GETC();
    }

    if (!isdigit(c)) {
        ERROR("number: digit expected");
        return NULL;
    }

    while (isdigit(c)) {
        expo *= 10;
        expo += c - '0';
        c = GETC();
    }

skipexpo:
    UNGETC(c);

    if (dbl) {
        dval = sign * (long long) ival;
        dval += sign * frac;
        dval *= pow(10.0, (double) signexpo * expo);
    }

    zzjson = config->calloc(1, sizeof(ZZJSON));
    if (!zzjson) {
        MEMERROR();
        return NULL;
    }
    if (dbl) {
        zzjson->type = ZZJSON_NUMBER_DOUBLE;
        zzjson->value.number.val.dval = dval;
    } else {
        zzjson->type = sign < 0 ? ZZJSON_NUMBER_NEGINT : ZZJSON_NUMBER_POSINT;
        zzjson->value.number.val.ival = ival;
    }
    
    return zzjson;
}

static ZZJSON *parse_literal(ZZJSON_CONFIG *config, char *s, ZZJSON_TYPE t) {
    char b[strlen(s)+1];
    unsigned int i;

    for (i=0; i<strlen(s); i++) b[i] = GETC();
    b[i] = 0;

    if (!strcmp(b,s)) {
        ZZJSON *zzjson;
        zzjson = config->calloc(1, sizeof(ZZJSON));
        if (!zzjson) {
            MEMERROR();
            return NULL;
        }
        zzjson->type = t;
        return zzjson;
    }
    ERROR("literal: expected %s", s);
    return NULL;
}

static ZZJSON *parse_true(ZZJSON_CONFIG *config) {
    return parse_literal(config, (char *)"true", ZZJSON_TRUE);
}

static ZZJSON *parse_false(ZZJSON_CONFIG *config) {
    return parse_literal(config, (char *)"false", ZZJSON_FALSE);
}

static ZZJSON *parse_null(ZZJSON_CONFIG *config) {
    return parse_literal(config, (char *)"null", ZZJSON_NULL);
}

static ZZJSON *parse_value(ZZJSON_CONFIG *config) {
    ZZJSON *retval = NULL;
    int c;

    SKIPWS();
    c = GETC();
    UNGETC(c);
    switch (c) {
        case '"':   retval = parse_string2(config); break;
        case '0': case '1': case '2': case '3': case '4': case '5':
        case '6': case '7': case '8': case '9': case '-':
                    retval = parse_number(config); break;
        case '{':   retval = parse_object(config); break;
        case '[':   retval = parse_array(config); break;
        case 't':   retval = parse_true(config); break;
        case 'f':   retval = parse_false(config); break;
        case 'n':   retval = parse_null(config); break;
    }

    if (!retval) {
        ERROR("value: invalid value");
        return retval;
    }

    return retval;
}

static ZZJSON *parse_array(ZZJSON_CONFIG *config) {
    ZZJSON *retval = NULL, **next = &retval;
    int c;

    SKIPWS();
    c = GETC();
    if (c != '[') {
        ERROR("array: expected '['");
        return NULL;
    }

    SKIPWS();
    c = GETC();
    while (c > 0 && c != ']') {
        ZZJSON *zzjson = NULL, *val = NULL;

        UNGETC(c);

        SKIPWS();
        val = parse_value(config);
        if (!val) {
            ERROR("array: value expected");
            goto errout;
        }

        SKIPWS();
        c = GETC();
        if (c != ',' && c != ']') {
            ERROR("array: expected ',' or ']'");
errout_with_val:
            zzjson_free(config, val);
            goto errout;
        }
        if (c == ',') {
            SKIPWS();
            c = GETC();
            if (c == ']' && !ALLOW_EXTRA_COMMA) {
                ERROR("array: expected value after ','");
                goto errout_with_val;
            }
        }
        UNGETC(c);

        zzjson = config->calloc(1, sizeof(ZZJSON));
        if (!zzjson) {
            MEMERROR();
            zzjson_free(config, val);
            goto errout_with_val;
        }
        zzjson->type            = ZZJSON_ARRAY;
        zzjson->value.array.val = val;
        *next = zzjson;
        next = &zzjson->next;

        c = GETC();
    }

    if (c != ']') {
        ERROR("array: expected ']'");
        goto errout;
    }

    if (!retval) {  /* empty array, [ ] */
        retval = config->calloc(1, sizeof(ZZJSON));
        if (!retval) {
            MEMERROR();
            return NULL;
        }
        retval->type = ZZJSON_ARRAY;
    }
            
    return retval;

errout:
    zzjson_free(config, retval);
    return NULL;
}

static ZZJSON *parse_object(ZZJSON_CONFIG *config) {
    ZZJSON *retval = NULL;
    int c;
    ZZJSON **next = &retval;

    SKIPWS();
    c = GETC();
    if (c != '{') {
        ERROR("object: expected '{'");
        return NULL;
    }

    SKIPWS();
    c = GETC();
    while (c > 0 && c != '}') {
        ZZJSON *zzjson = NULL, *val = NULL;
        char *str;

        UNGETC(c);

        str = parse_string(config);
        if (!str) {
            ERROR("object: expected string");
errout_with_str:
            config->free(str);
            goto errout;
        }

        SKIPWS();
        c = GETC();
        if (c != ':') {
            ERROR("object: expected ':'");
            goto errout_with_str;
        }

        SKIPWS();
        val = parse_value(config);
        if (!val) {
            ERROR("object: value expected");
            goto errout_with_str;
        }

        SKIPWS();
        c = GETC();
        if (c != ',' && c != '}') {
            ERROR("object: expected ',' or '}'");
errout_with_str_and_val:
            zzjson_free(config, val);
            goto errout_with_str;
        }
        if (c == ',') {
            SKIPWS();
            c = GETC();
            if (c == '}' && !ALLOW_EXTRA_COMMA) {
                ERROR("object: expected pair after ','");
                goto errout_with_str_and_val;
            }
        }
        UNGETC(c);

        zzjson = config->calloc(1, sizeof(ZZJSON));
        if (!zzjson) {
            MEMERROR();
            goto errout_with_str_and_val;
        }
        zzjson->type                = ZZJSON_OBJECT;
        zzjson->value.object.label  = str;
        zzjson->value.object.val    = val;
        *next = zzjson;
        next = &zzjson->next;

        c = GETC();
    }

    if (c != '}') {
        ERROR("object: expected '}'");
        goto errout;
    }

    if (!retval) {  /* empty object, { } */
        retval = config->calloc(1, sizeof(ZZJSON));
        if (!retval) {
            MEMERROR();
            return NULL;
        }
        retval->type = ZZJSON_OBJECT;
    }
            
    return retval;

errout:
    zzjson_free(config, retval);
    return NULL;
}

ZZJSON *zzjson_parse(ZZJSON_CONFIG *config) {
    ZZJSON *retval;
    int c;

    SKIPWS();   
    c = GETC();
    UNGETC(c);
    if (c == '[')       retval = parse_array(config);
    else if (c == '{')  retval = parse_object(config);
    else                { ERROR("expected '[' or '{'"); return NULL; }

    if (!retval) return NULL;

    SKIPWS();
    c = GETC();
    if (c >= 0 && !ALLOW_GARBAGE_AT_END) {
        ERROR("parse: garbage at end of file");
        zzjson_free(config, retval);
        return NULL;
    }

    return retval;
}
