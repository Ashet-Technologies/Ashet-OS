/*
 * abort.c
 */

#include <stdlib.h>
#include <unistd.h>

void abort(void)
{
    _exit(255);
}
