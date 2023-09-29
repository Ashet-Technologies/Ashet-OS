/* JSON Create ZZJSON structures
 * ZZJSON - Copyright (C) 2008 by Ivo van Poorten
 * License: GNU Lesser General Public License version 2.1
 */

#include "zzjson.h"
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#ifdef CONFIG_NO_ERROR_MESSAGES
#define ERROR(x...)
#else
#define ERROR(x...)     config->error(config->ehandle, ##x)
#endif
#define MEMERROR()      ERROR("out of memory")

static ZZJSON *zzjson_create_templ(ZZJSON_CONFIG *config, ZZJSON_TYPE type) {
    ZZJSON *zzjson = config->calloc(1, sizeof(ZZJSON));
    if (!zzjson) MEMERROR();
    else         zzjson->type = type;
    return zzjson;
}

ZZJSON *zzjson_create_true(ZZJSON_CONFIG *config) {
    return zzjson_create_templ(config, ZZJSON_TRUE);
}

ZZJSON *zzjson_create_false(ZZJSON_CONFIG *config) {
    return zzjson_create_templ(config, ZZJSON_FALSE);
}

ZZJSON *zzjson_create_null(ZZJSON_CONFIG *config) {
    return zzjson_create_templ(config, ZZJSON_NULL);
}

ZZJSON *zzjson_create_number_d(ZZJSON_CONFIG *config, double d) {
    ZZJSON *zzjson = zzjson_create_templ(config, ZZJSON_NUMBER_DOUBLE);
    if (zzjson)
        zzjson->value.number.val.dval = d;
    return zzjson;
}

ZZJSON *zzjson_create_number_i(ZZJSON_CONFIG *config, long long i) {
    ZZJSON *zzjson = zzjson_create_templ(config, ZZJSON_NUMBER_NEGINT);
    if (zzjson) {
        zzjson->type = i<0LL ? ZZJSON_NUMBER_NEGINT : ZZJSON_NUMBER_POSINT;
        zzjson->value.number.val.ival = llabs(i);
    }
    return zzjson;
}

/* sdup mimics strdup, but avoids having another function pointer in config */
static char *sdup(ZZJSON_CONFIG *config, char *s) {
    size_t slen = strlen(s)+1;
    char *scopy = config->malloc(slen);

    if (!scopy) MEMERROR();
    else        memcpy(scopy, s, slen);
    return scopy;
}

ZZJSON *zzjson_create_string(ZZJSON_CONFIG *config, char *s) {
    ZZJSON *zzjson = NULL;
    char *scopy;
        
    if (!(scopy = sdup(config,s))) return zzjson;

    if ((zzjson = zzjson_create_templ(config, ZZJSON_STRING)))
        zzjson->value.string.string = scopy;
    else
        config->free(scopy);

    return zzjson;
}

ZZJSON *zzjson_create_array(ZZJSON_CONFIG *config, ...) {
    ZZJSON *zzjson, *retval, *val;
    va_list ap;

    if (!(zzjson = zzjson_create_templ(config, ZZJSON_ARRAY))) return zzjson;
    retval = zzjson;

    va_start(ap, config);
    val = va_arg(ap, ZZJSON *);
    while (val) {
        zzjson->value.array.val = val;
        val = va_arg(ap, ZZJSON *);

        if (val) {
            ZZJSON *next = zzjson_create_templ(config, ZZJSON_ARRAY);
            if (!next) {
                while (retval) {
                    next = retval->next;
                    config->free(retval);
                    retval = next;
                }
                break;
            }
            zzjson->next = next;
            zzjson = next;
        }
    }
    va_end(ap);
    return retval;
}

ZZJSON *zzjson_create_object(ZZJSON_CONFIG *config, ...) {
    ZZJSON *zzjson, *retval, *val;
    char *label, *labelcopy;
    va_list ap;

    if (!(zzjson = zzjson_create_templ(config, ZZJSON_OBJECT))) return zzjson;
    retval = zzjson;

    va_start(ap, config);
    label = va_arg(ap, char *);
    while (label) {
        val = va_arg(ap, ZZJSON *);
        labelcopy = sdup(config, label);

        if (!labelcopy) {
            zzjson_free(config, retval);
            retval = NULL;
            break;
        }

        zzjson->value.object.label  = labelcopy;
        zzjson->value.object.val    = val;

        label = va_arg(ap, char *);

        if (label) {
            ZZJSON *next = zzjson_create_templ(config, ZZJSON_OBJECT);
            if (!next) {
                while (retval) {
                    next = retval->next;
                    config->free(retval->value.object.label);
                    config->free(retval);
                    retval = next;
                }
                break;
            }
            zzjson->next = next;
            zzjson = next;
        }
    }
    va_end(ap);
    return retval;
}

ZZJSON *zzjson_array_prepend(ZZJSON_CONFIG *config, ZZJSON *array,
                                                    ZZJSON *val) {
    ZZJSON *zzjson;

    if (!array->value.array.val) { /* empty array */
        array->value.array.val = val;
        return array;
    }

    zzjson = zzjson_create_templ(config, ZZJSON_ARRAY);
    if (zzjson) {
        zzjson->value.array.val = val;
        zzjson->next = array;
    }
    return zzjson;
}

ZZJSON *zzjson_array_append(ZZJSON_CONFIG *config, ZZJSON *array,
                                                   ZZJSON *val) {
    ZZJSON *retval = array, *zzjson;

    if (!array->value.array.val) { /* empty array */
        array->value.array.val = val;
        return array;
    }

    zzjson = zzjson_create_templ(config, ZZJSON_ARRAY);
    if (!zzjson) return NULL;

    while (array->next) array = array->next;

    zzjson->value.array.val = val;
    array->next = zzjson;

    return retval;
}

ZZJSON *zzjson_object_prepend(ZZJSON_CONFIG *config, ZZJSON *object,
                              char *label, ZZJSON *val) {
    ZZJSON *zzjson = NULL;
    char *labelcopy = sdup(config, label);

    if (!labelcopy) return zzjson;

    if (!object->value.object.label) { /* empty object */
        object->value.object.label  = labelcopy;
        object->value.object.val    = val;
        return object;
    }

    zzjson = zzjson_create_templ(config, ZZJSON_OBJECT);
    if (zzjson) {
        zzjson->value.object.label  = labelcopy;
        zzjson->value.object.val    = val;
        zzjson->next = object;
    } else {
        config->free(labelcopy);
    }
    return zzjson;
}

ZZJSON *zzjson_object_append(ZZJSON_CONFIG *config, ZZJSON *object,
                             char *label, ZZJSON *val) {
    ZZJSON *retval = object, *zzjson = NULL;
    char *labelcopy = sdup(config, label);

    if (!labelcopy) return zzjson;

    if (!object->value.object.label) { /* empty object */
        object->value.object.label  = labelcopy;
        object->value.object.val    = val;
        return object;
    }

    zzjson = zzjson_create_templ(config, ZZJSON_OBJECT);
    if (!zzjson) {
        config->free(labelcopy);
        return NULL;
    }

    while (object->next) object = object->next;

    zzjson->value.object.label  = labelcopy;
    zzjson->value.object.val    = val;
    object->next = zzjson;

    return retval;
}

