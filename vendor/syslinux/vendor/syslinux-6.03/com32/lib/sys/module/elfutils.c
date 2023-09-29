#include <stdlib.h>
#include <errno.h>

#include "elfutils.h"

unsigned long elf_hash(const unsigned char *name) {
	unsigned long h = 0;
	unsigned long g;

	while (*name) {
		h = (h << 4) + *name++;
		if ((g = h & 0xF0000000))
			h ^= g >> 24;

		h &= ~g;
	}

	return h;
}

unsigned long elf_gnu_hash(const unsigned char *name) {
	unsigned long h = 5381;
	unsigned char c;

	for (c = *name; c != '\0'; c = *++name) {
		h = h * 33 + c;
	}

	return h & 0xFFFFFFFF;
}

#ifndef HAVE_ELF_POSIX_MEMALIGN

struct memalign_info {
	void 	*start_addr;
	char	data[0];
};

int elf_malloc(void **memptr, size_t alignment, size_t size) {
	char *start_addr = NULL;
	struct memalign_info *info;

	if ((alignment & (alignment - 1)) != 0)
		return EINVAL;
	if (alignment % sizeof(void*) != 0)
		alignment = sizeof(void*);

	start_addr = malloc(size + (alignment > sizeof(struct memalign_info) ?
					alignment : sizeof(struct memalign_info)));

	if (start_addr == NULL)
		return ENOMEM;


	info = (struct memalign_info*)(start_addr -
			((unsigned long)start_addr % alignment) +
			alignment - sizeof(struct memalign_info));

	info->start_addr = start_addr;

	*memptr = info->data;

	return 0;
}

void elf_free(char *memptr) {
	struct memalign_info *info = (struct memalign_info*)(memptr -
			sizeof(struct memalign_info));

	free(info->start_addr);
}

#else

int elf_malloc(void **memptr, size_t alignment, size_t size) {
	if ((alignment & (alignment - 1)) != 0)
		return EINVAL;

	if (alignment % sizeof(void*) != 0)
		alignment = sizeof(void*);

	return posix_memalign(memptr, alignment, size);
}

void elf_free(void *memptr) {
	free(memptr);
}

#endif //HAVE_ELF_POSIX_MEMALIGN
