/* JSON query
 * ZZJSON - Copyright (C) 2008 by Ivo van Poorten
 * License: GNU Lesser General Public License version 2.1
 */

#include "zzjson.h"
#include <string.h>
#include <stdarg.h>

ZZJSON *zzjson_object_find_label(ZZJSON *zzjson, char *label) {
    if (zzjson->type != ZZJSON_OBJECT) return NULL;

    while (zzjson) {
        char *string = zzjson->value.object.label;

        if (zzjson->type != ZZJSON_OBJECT) return NULL;
        if (!string)                       return NULL;

        if (!strcmp(string, label))
            return zzjson->value.object.val;
        zzjson = zzjson->next;
    }
    return NULL;
}

ZZJSON *zzjson_object_find_labels(ZZJSON *zzjson, ...) {
    va_list ap;
    char *lbl;

    va_start(ap, zzjson);
    lbl = va_arg(ap, char *);
    while (lbl) {
        zzjson = zzjson_object_find_label(zzjson, lbl);
        if (!zzjson) break;
        lbl = va_arg(ap, char *);
    }
    va_end(ap);

    return zzjson;
}

unsigned int zzjson_object_count(ZZJSON *zzjson) {
    unsigned int count = 1;

    if (zzjson->type != ZZJSON_OBJECT) return 0;
    if (!zzjson->value.object.label)   return 0; /* empty { } */

    while ((zzjson = zzjson->next)) count++;

    return count;
}

unsigned int zzjson_array_count(ZZJSON *zzjson) {
    unsigned int count = 1;

    if (zzjson->type != ZZJSON_ARRAY) return 0;
    if (!zzjson->value.array.val)     return 0; /* empty [ ] */

    while ((zzjson = zzjson->next)) count++;

    return count;
}

