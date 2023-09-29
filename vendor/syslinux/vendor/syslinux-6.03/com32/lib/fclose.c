/*
 * fclose.c
 */

#include <stdio.h>
#include <unistd.h>

int fclose(FILE * __f)
{
    return close(fileno(__f));
}
