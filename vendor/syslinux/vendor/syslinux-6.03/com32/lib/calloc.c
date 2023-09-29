/*
 * calloc.c
 */

#include <stdlib.h>
#include <string.h>

/* FIXME: This should look for multiplication overflow */

void *calloc(size_t nmemb, size_t size)
{
    return zalloc(size * nmemb);
}
