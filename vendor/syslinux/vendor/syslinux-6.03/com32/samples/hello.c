/*
 * hello.c - A simple ELF module that sorts a couple of numbers
 *
 *  Created on: Aug 11, 2008
 *      Author: Stefan Bucur <stefanb@zytor.com>
 */

#include <stdio.h>
#include <stdlib.h>

#include "sort.h"

#define NUM_COUNT		10
#define MAX_NUM			100

int main(int argc __unused, char **argv __unused)
{
    int *nums = NULL;

    nums = malloc(NUM_COUNT * sizeof(int));
    printf("Hello, world, from 0x%08X! malloc return %p\n", (unsigned int)&main, nums);

    free(nums);

    return 0;
}
