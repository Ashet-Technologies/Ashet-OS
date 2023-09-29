/*
 * Copyright 2012-2014 Intel Corporation - All Rights Reserved
 */

#include <mem/malloc.h>
#include <string.h>
#include "efi.h"

void *efi_malloc(size_t size, enum heap heap, malloc_tag_t tag)
{
	return AllocatePool(size);
}

void *efi_realloc(void *ptr, size_t size)
{
	void *newptr;

	newptr = AllocatePool(size);
	memcpy(newptr, ptr, size);
	FreePool(ptr);
	return newptr;
}

void efi_free(void *ptr)
{
	FreePool(ptr);
}
