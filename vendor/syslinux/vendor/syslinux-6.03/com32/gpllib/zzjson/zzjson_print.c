/* JSON Printer
 * ZZJSON - Copyright (C) 2008 by Ivo van Poorten
 * License: GNU Lesser General Public License version 2.1
 */

#include "zzjson.h"

#define PRINT(fmt...) if (config->print(config->ohandle, ##fmt) < 0) return -1;
//#define PUTC(c)       if (config->putchar(c, config->ohandle) < 0) return -1;
#define PUTC(c)       PRINT("%c",c)
#define INC 4

static int print_string(ZZJSON_CONFIG *config, char *s) {
    int c, bs;
    if (!s) return 0;
    while ((c = *s++)) {
        bs = 1;
        switch (c) {
//            case '/':                 // useless escape of forward slash
            case '\\':
                if (*s == 'u') bs = 0;  // copy \uHHHH verbatim
                break;
            case '"':               break;
            case '\b':  c = 'b';    break;
            case '\f':  c = 'f';    break;
            case '\n':  c = 'n';    break;
            case '\r':  c = 'r';    break;
            case '\t':  c = 't';    break;
            default:    bs = 0;     break;
        }
        if (bs) PUTC('\\');
        PUTC(c);
    }
    return 0;
}

static int zzjson_print2(ZZJSON_CONFIG *config, ZZJSON *zzjson,
                 unsigned int indent, unsigned int objval) {
    char c = 0, d = 0;
    if (!zzjson) return -1;

    switch(zzjson->type) {
        case ZZJSON_OBJECT: c = '{'; d = '}'; break;
        case ZZJSON_ARRAY:  c = '['; d = ']'; break;
        default: break;
    }

    if (c) PRINT("%s%*s%c", indent ? "\n" : "", indent, "", c);

    while (zzjson) {
        switch(zzjson->type) {
        case ZZJSON_OBJECT:
            if (zzjson->value.object.val) {
                PRINT("\n%*s\"", indent+INC, "");
                if (print_string(config, zzjson->value.object.label) < 0)
                    return -1;
                PRINT("\" :");
                if (zzjson_print2(config, zzjson->value.object.val,
                                                indent+INC, 1) < 0) return -1;
            }
            break;
        case ZZJSON_ARRAY:
            if (zzjson->value.array.val)
                if (zzjson_print2(config, zzjson->value.array.val,
                                                indent+INC, 0) < 0) return -1;
            break;
        case ZZJSON_STRING:
            PRINT(objval ? " \"" : "\n%*s\"", indent, "");
            if (print_string(config, zzjson->value.string.string)<0) return -1;
            PUTC('"');
            break;
        case ZZJSON_FALSE:
            PRINT(objval ? " false" : "\n%*sfalse", indent, "");
            break;
        case ZZJSON_NULL:
            PRINT(objval ? " null" : "\n%*snull", indent, "");
            break;
        case ZZJSON_TRUE:
            PRINT(objval ? " true" : "\n%*strue", indent, "");
            break;
        case ZZJSON_NUMBER_NEGINT:
        case ZZJSON_NUMBER_POSINT:
        case ZZJSON_NUMBER_DOUBLE:
            PRINT(objval ? " " : "\n%*s", indent, "");
            if (zzjson->type == ZZJSON_NUMBER_DOUBLE) {
                PRINT("%16.16e", zzjson->value.number.val.dval);
            } else {
                if (zzjson->type == ZZJSON_NUMBER_NEGINT) PUTC('-');
                PRINT("%llu", zzjson->value.number.val.ival);
            }
        default:
            break;
        }
        zzjson = zzjson->next;
        if (zzjson) PUTC(',');
    }

    if (d) PRINT("\n%*s%c", indent, "", d);

    return 0;
}

int zzjson_print(ZZJSON_CONFIG *config, ZZJSON *zzjson) {
    int retval = zzjson_print2(config, zzjson, 0, 0);
//    if (retval >= 0) retval = config->putchar('\n', config->ohandle);
#ifndef CONFIG_NO_ERROR_MESSAGES
    if (retval <  0) config->error(config->ehandle, "print: unable to print");
#endif
    return retval;
}
