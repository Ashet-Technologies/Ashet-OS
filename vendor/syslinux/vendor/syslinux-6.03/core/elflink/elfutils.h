#ifndef ELF_UTILS_H_
#define ELF_UTILS_H_

#include <elf.h>
#include <stdlib.h>

/**
 * elf_get_header - Returns a pointer to the ELF header structure.
 * @elf_image: pointer to the ELF file image in memory
 */
static inline Elf32_Ehdr *elf_get_header(void *elf_image)
{
    return (Elf32_Ehdr *) elf_image;
}

/**
 * elf_get_pht - Returns a pointer to the first entry in the PHT.
 * @elf_image: pointer to the ELF file image in memory
 */
static inline Elf32_Phdr *elf_get_pht(void *elf_image)
{
    Elf32_Ehdr *elf_hdr = elf_get_header(elf_image);

    return (Elf32_Phdr *) ((Elf32_Off) elf_hdr + elf_hdr->e_phoff);
}

//
/**
 * elf_get_ph - Returns the element with the given index in the PTH
 * @elf_image: pointer to the ELF file image in memory
 * @index: the index of the PHT entry to look for
 */
static inline Elf32_Phdr *elf_get_ph(void *elf_image, int index)
{
    Elf32_Phdr *elf_pht = elf_get_pht(elf_image);
    Elf32_Ehdr *elf_hdr = elf_get_header(elf_image);

    return (Elf32_Phdr *) ((Elf32_Off) elf_pht + index * elf_hdr->e_phentsize);
}

/**
 * elf_hash - Returns the index in a SysV hash table for the symbol name.
 * @name: the name of the symbol to look for
 */
extern unsigned long elf_hash(const unsigned char *name);

/**
 * elf_gnu_hash - Returns the index in a GNU hash table for the symbol name.
 * @name: the name of the symbol to look for
 */
extern unsigned long elf_gnu_hash(const unsigned char *name);

/**
 * elf_malloc - Allocates memory to be used by ELF module contents.
 * @memptr: pointer to a variable to hold the address of the allocated block.
 * @alignment: alignment constraints of the block
 * @size: the required size of the block
 */
extern int elf_malloc(void **memptr, size_t alignment, size_t size);

/**
 * elf_free - Releases memory previously allocated by elf_malloc.
 * @memptr: the address of the allocated block
 */
extern void elf_free(void *memptr);

#endif /*ELF_UTILS_H_ */
