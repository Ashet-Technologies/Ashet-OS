/* JSON free
 * ZZJSON - Copyright (C) 2008 by Ivo van Poorten
 * License: GNU Lesser General Public License version 2.1
 */

#include "zzjson.h"

void zzjson_free(ZZJSON_CONFIG *config, ZZJSON *zzjson) {
    while (zzjson) {
        ZZJSON *next;
        switch(zzjson->type) {
            case ZZJSON_OBJECT:
                config->free(zzjson->value.object.label);
                zzjson_free(config, zzjson->value.object.val);
                break;
            case ZZJSON_ARRAY:
                zzjson_free(config, zzjson->value.array.val);
                break;
            case ZZJSON_STRING:
                config->free(zzjson->value.string.string);
                break;
            default:
                break;
        }
        next = zzjson->next;
        config->free(zzjson);
        zzjson = next;
    }
}
