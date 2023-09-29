/*
 * sort.c - Sample ELF module providing a quick sort function
 *
 *  Created on: Aug 11, 2008
 *      Author: Stefan Bucur <stefanb@zytor.com>
 */

#include <stdlib.h>

static inline void swap(int *x, int *y)
{
    int tmp;
    tmp = *x;
    *x = *y;
    *y = tmp;
}

static inline int randint(int l, int u)
{
    return l + (rand() % (u - l + 1));
}

/**
 * quick_sort_range - A small and efficient version of quicksort.
 * @nums: The numbers to sort
 * @l: The lower index in the vector (inclusive)
 * @u: The upper index in the vector (inclusive)
 *
 * The implementation is taken from "Beautiful Code", by O'Reilly, the
 * book students received from Google as a gift for their acceptance
 * in the GSoC 2008 program. The code belongs to Jon Bentley, who
 * wrote the third chapter of the book. Since ELF modules were written
 * as part of this program, the author of the module considered
 * the book had to be put to some use. :)
 */
static void quick_sort_range(int *nums, int l, int u)
{
    int i, m;
    if (l >= u)
	return;

    swap(&nums[l], &nums[randint(l, u)]);

    m = l;
    for (i = l + 1; i <= u; i++) {
	if (nums[i] < nums[l])
	    swap(&nums[++m], &nums[i]);
    }

    swap(&nums[l], &nums[m]);

    quick_sort_range(nums, l, m - 1);
    quick_sort_range(nums, m + 1, u);
}

void quick_sort(int *nums, int count)
{
    quick_sort_range(nums, 0, count - 1);
}
