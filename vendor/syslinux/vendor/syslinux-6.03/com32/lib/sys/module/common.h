/*
 * common.h - Common internal operations performed by the module subsystem
 *
 *  Created on: Aug 11, 2008
 *      Author: Stefan Bucur <stefanb@zytor.com>
 */

#ifndef COMMON_H_
#define COMMON_H_

#include <stdio.h>

#include <sys/module.h>
#include <linux/list.h>

#include "elfutils.h"

// Performs an operation and jumps to a given label if an error occurs
#define CHECKED(res, expr, error)		\
	do { 								\
		(res) = (expr);					\
		if ((res) < 0)					\
			goto error;					\
	} while (0)

#define MIN(x,y)	(((x) < (y)) ? (x) : (y))
#define MAX(x,y)	(((x) > (y)) ? (x) : (y))

static inline Elf_Sym *symbol_get_entry(struct elf_module *module, int entry)
{
	char *sym_table = (char *)module->sym_table;
	int index = entry * module->syment_size;

	return (Elf_Sym *)(sym_table + index);
}

//#define ELF_DEBUG

#ifdef ELF_DEBUG
#define DBG_PRINT(fmt, args...)	fprintf(stderr, "[ELF] " fmt, ##args)
#else
#define DBG_PRINT(fmt, args...)	// Expand to nothing
#endif

// User-space debugging routines
#ifdef ELF_DEBUG
extern void print_elf_ehdr(Elf_Ehdr *ehdr);
extern void print_elf_symbols(struct elf_module *module);
#endif //ELF_DEBUG


/*
 * Image files manipulation routines
 */

extern int image_load(struct elf_module *module);
extern int image_unload(struct elf_module *module);
extern int image_read(void *buff, size_t size, struct elf_module *module);
extern int image_skip(size_t size, struct elf_module *module);
extern int image_seek(Elf_Off offset, struct elf_module *module);

extern struct module_dep *module_dep_alloc(struct elf_module *module);

extern int check_header_common(Elf_Ehdr *elf_hdr);

extern int enforce_dependency(struct elf_module *req, struct elf_module *dep);
extern int clear_dependency(struct elf_module *req, struct elf_module *dep);

extern int check_symbols(struct elf_module *module);


#endif /* COMMON_H_ */
