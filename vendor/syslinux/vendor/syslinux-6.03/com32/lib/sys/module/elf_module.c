/*
 * elf_module.c
 *
 *  Created on: Aug 11, 2008
 *      Author: Stefan Bucur <stefanb@zytor.com>
 */

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <elf.h>
#include <dprintf.h>
#include <core.h>

#include <linux/list.h>
#include <sys/module.h>
#include <sys/exec.h>

#include "elfutils.h"
#include "common.h"

static int check_header(Elf_Ehdr *elf_hdr) {
	int res;

	res = check_header_common(elf_hdr);

	if (res != 0)
		return res;

	if (elf_hdr->e_type != MODULE_ELF_TYPE) {
		dprintf("The ELF file must be a shared object\n");
		return -1;
	}

	if (elf_hdr->e_phoff == 0x00000000) {
		dprintf("PHT missing\n");
		return -1;
	}

	return 0;
}

/*
 *
 * The implementation assumes that the loadable segments are present
 * in the PHT sorted by their offsets, so that only forward seeks would
 * be necessary.
 */
extern int load_segments(struct elf_module *module, Elf_Ehdr *elf_hdr);

static int prepare_dynlinking(struct elf_module *module) {
	Elf_Dyn  *dyn_entry = module->dyn_table;

	while (dyn_entry->d_tag != DT_NULL) {
		switch (dyn_entry->d_tag) {
		case DT_NEEDED:
			/*
			 * It's unlikely there'll be more than
			 * MAX_NR_DEPS DT_NEEDED entries but if there
			 * are then inform the user that we ran out of
			 * space.
			 */
			if (module->nr_needed < MAX_NR_DEPS)
				module->needed[module->nr_needed++] = dyn_entry->d_un.d_ptr;
			else {
				printf("Too many dependencies!\n");
				return -1;
			}
			break;
		case DT_HASH:
			module->hash_table =
				(Elf_Word*)module_get_absolute(dyn_entry->d_un.d_ptr, module);
			break;
		case DT_GNU_HASH:
			module->ghash_table =
				(Elf_Word*)module_get_absolute(dyn_entry->d_un.d_ptr, module);
			break;
		case DT_STRTAB:
			module->str_table =
				(char*)module_get_absolute(dyn_entry->d_un.d_ptr, module);
			break;
		case DT_SYMTAB:
			module->sym_table =
				module_get_absolute(dyn_entry->d_un.d_ptr, module);
			break;
		case DT_STRSZ:
			module->strtable_size = dyn_entry->d_un.d_val;
			break;
		case DT_SYMENT:
			module->syment_size = dyn_entry->d_un.d_val;
			break;
		case DT_PLTGOT: // The first entry in the GOT
			module->got = module_get_absolute(dyn_entry->d_un.d_ptr, module);
			break;
		}

		dyn_entry++;
	}

	return 0;
}

void undefined_symbol(void)
{
	printf("Error: An undefined symbol was referenced\n");
	kaboom();
}

extern int perform_relocation(struct elf_module *module, Elf_Rel *rel);
extern int resolve_symbols(struct elf_module *module);

static int extract_operations(struct elf_module *module) {
	Elf_Sym *ctors_start, *ctors_end;
	Elf_Sym *dtors_start, *dtors_end;
	module_ctor_t *ctors = NULL;
	module_ctor_t *dtors = NULL;

	ctors_start = module_find_symbol("__ctors_start", module);
	ctors_end = module_find_symbol("__ctors_end", module);

	if (ctors_start && ctors_end) {
		module_ctor_t *start, *end;
		int nr_ctors = 0;
		int i, size;

		start = module_get_absolute(ctors_start->st_value, module);
		end = module_get_absolute(ctors_end->st_value, module);

		nr_ctors = end - start;

		size = nr_ctors * sizeof(module_ctor_t);
		size += sizeof(module_ctor_t); /* NULL entry */

		ctors = malloc(size);
		if (!ctors) {
			printf("Unable to alloc memory for ctors\n");
			return -1;
		}

		memset(ctors, 0, size);
		for (i = 0; i < nr_ctors; i++)
			ctors[i] = start[i];

		module->ctors = ctors;
	}

	dtors_start = module_find_symbol("__dtors_start", module);
	dtors_end = module_find_symbol("__dtors_end", module);

	if (dtors_start && dtors_end) {
		module_ctor_t *start, *end;
		int nr_dtors = 0;
		int i, size;

		start = module_get_absolute(dtors_start->st_value, module);
		end = module_get_absolute(dtors_end->st_value, module);

		nr_dtors = end - start;

		size = nr_dtors * sizeof(module_ctor_t);
		size += sizeof(module_ctor_t); /* NULL entry */

		dtors = malloc(size);
		if (!dtors) {
			printf("Unable to alloc memory for dtors\n");
			free(ctors);
			return -1;
		}

		memset(dtors, 0, size);
		for (i = 0; i < nr_dtors; i++)
			dtors[i] = start[i];

		module->dtors = dtors;
	}

	return 0;
}

// Loads the module into the system
int module_load(struct elf_module *module) {
	int res;
	Elf_Sym *main_sym;
	Elf_Ehdr elf_hdr;
	module_ctor_t *ctor;
	struct elf_module *head = NULL;

	// Do not allow duplicate modules
	if (module_find(module->name) != NULL) {
		dprintf("Module %s is already loaded.\n", module->name);
		return EEXIST;
	}

	// Get a mapping/copy of the ELF file in memory
	res = image_load(module);

	if (res < 0) {
		dprintf("Image load failed for %s\n", module->name);
		return res;
	}

	// The module is a fully featured dynamic library
	module->shallow = 0;

	CHECKED(res, image_read(&elf_hdr, sizeof(Elf_Ehdr), module), error);
	//printf("check... 1\n");
	
	//print_elf_ehdr(&elf_hdr);

	// Checking the header signature and members
	CHECKED(res, check_header(&elf_hdr), error);
	//printf("check... 2\n");

	// Load the segments in the memory
	CHECKED(res, load_segments(module, &elf_hdr), error);
	//printf("bleah... 3\n");
	// Obtain dynamic linking information
	CHECKED(res, prepare_dynlinking(module), error);
	//printf("check... 4\n");

	head = module_current();

	/* Find modules we need to load as dependencies */
	if (module->str_table) {
		int i;

		/*
		 * Note that we have to load the dependencies in
		 * reverse order.
		 */
		for (i = module->nr_needed - 1; i >= 0; i--) {
			char *dep, *p;
			char *argv[2] = { NULL, NULL };

			dep = module->str_table + module->needed[i];

			/* strip everything but the last component */
			if (!strlen(dep))
				continue;

			if (strchr(dep, '/')) {
				p = strrchr(dep, '/');
				p++;
			} else
				p = dep;

			argv[0] = p;
			res = spawn_load(p, 1, argv);
			if (res < 0) {
				printf("Failed to load %s\n", p);
				goto error;
			}
		}
	}

	// Check the symbols for duplicates / missing definitions
	CHECKED(res, check_symbols(module), error);
	//printf("check... 5\n");

	main_sym = module_find_symbol("main", module);
	if (main_sym)
		module->main_func =
			module_get_absolute(main_sym->st_value, module);

	//printf("check... 6\n");

	// Add the module at the beginning of the module list
	list_add(&module->list, &modules_head);

	// Perform the relocations
	resolve_symbols(module);

	// Obtain constructors and destructors
	CHECKED(res, extract_operations(module), error);

	//dprintf("module->symtable_size = %d\n", module->symtable_size);

	//print_elf_symbols(module);

	// The file image is no longer needed
	image_unload(module);

	/*
	dprintf("MODULE %s LOADED SUCCESSFULLY (main@%p, init@%p, exit@%p)\n",
			module->name,
			(module->main_func == NULL) ? NULL : *(module->main_func),
			(module->init_func == NULL) ? NULL : *(module->init_func),
			(module->exit_func == NULL) ? NULL : *(module->exit_func));
	*/

	for (ctor = module->ctors; ctor && *ctor; ctor++)
		(*ctor) ();

	return 0;

error:
	if (head)
		unload_modules_since(head->name);

	// Remove the module from the module list (if applicable)
	list_del_init(&module->list);

	if (module->module_addr != NULL) {
		elf_free(module->module_addr);
		module->module_addr = NULL;
	}

	image_unload(module);

	// Clear the execution part of the module buffer
	memset(&module->u, 0, sizeof module->u);

	return res;
}

