/*
 * Display directory contents
 */
#include <stdlib.h>
#include <stdio.h>
#include <console.h>
#include <string.h>
#include <com32.h>
#include <zzjson/zzjson.h>
#include <stdarg.h>

static void myerror(void *ehandle, const char *format, ...) {
    va_list ap;
    fprintf(ehandle, "error: ");
    va_start(ap, format);
    vfprintf(ehandle, format, ap);
    va_end(ap);
    fputc('\n', ehandle);
}


int main(int argc, char *argv[])
{
#if 0
	/* this hangs! */
    openconsole(&dev_rawcon_r, &dev_stdcon_w);
#else
	/* this works */
    openconsole(&dev_rawcon_r, &dev_ansiserial_w);
#endif
    (void) argc;
    (void) argv;
    ZZJSON  *tmp;
    ZZJSON_CONFIG config = { ZZJSON_VERY_STRICT, NULL,
                             (int(*)(void*)) fgetc,
                             NULL,
                             malloc, calloc, free, realloc,
                             stderr, myerror, stdout,
                             (int(*)(void*,const char*,...)) fprintf,
                             (int(*)(int,void*)) fputc };
    
    do {
        ZZJSON *tmp2;

        tmp = zzjson_create_array(&config,
                zzjson_create_number_d(&config, 3.14),
                zzjson_create_number_i(&config, 1234LL),
                zzjson_create_number_i(&config, -4321LL),
                zzjson_create_true(&config),
                zzjson_create_false(&config),
                zzjson_create_null(&config),
                zzjson_create_string(&config, "hello, world"),
                zzjson_create_object(&config,
                    "picard", zzjson_create_string(&config, "jean-luc"),
                    "riker",  zzjson_create_string(&config, "william t."),
                    NULL),
                zzjson_create_object(&config, NULL),
                zzjson_create_array(&config, NULL),
                NULL );

        if (!tmp) {
            fprintf(stderr, "error during creation of json tree\n");
            break;
        }

        tmp2 = zzjson_array_prepend(&config, tmp,
                    zzjson_create_string(&config, "prepended string"));

        if (!tmp2) {
            fprintf(stderr, "error during prepend\n");
            break;
        }
        tmp = tmp2;

        tmp2 = zzjson_array_append(&config, tmp,
                    zzjson_create_string(&config, "appended string (slow)"));

        if (!tmp2) {
            fprintf(stderr, "error during append\n");
            break;
        }
        tmp = tmp2;

        zzjson_print(&config, tmp);
    } while(0);
    if (tmp) zzjson_free(&config, tmp);

    {
        tmp = zzjson_create_array(&config, NULL); /* empty array */
        tmp = zzjson_array_prepend(&config, tmp, zzjson_create_true(&config));
        zzjson_print(&config, tmp);
        zzjson_free(&config, tmp);
    }

    {
        tmp = zzjson_create_object(&config, NULL); /* empty object */
        tmp = zzjson_object_prepend(&config, tmp, "hello",
                                zzjson_create_string(&config, "world"));
        tmp = zzjson_object_append(&config, tmp, "goodbye",
                                zzjson_create_string(&config, "cruel world"));
        zzjson_print(&config, tmp);
        zzjson_free(&config, tmp);
    }

    return 0;
}
  
