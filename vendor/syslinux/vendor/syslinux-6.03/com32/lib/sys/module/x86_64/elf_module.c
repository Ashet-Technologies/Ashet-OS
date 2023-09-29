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
#include "../common.h"

/*
 *
 * The implementation assumes that the loadable segments are present
 * in the PHT sorted by their offsets, so that only forward seeks would
 * be necessary.
 */
int load_segments(struct elf_module *module, Elf_Ehdr *elf_hdr) {
	int i;
	int res = 0;
	char *pht = NULL;
	char *sht = NULL;
	Elf64_Phdr *cr_pht;
	Elf64_Shdr *cr_sht;

	Elf64_Addr min_addr  = 0x0000000000000000; // Min. ELF vaddr
	Elf64_Addr max_addr  = 0x0000000000000000; // Max. ELF vaddr
	Elf64_Word max_align = sizeof(void*); // Min. align of posix_memalign()
	Elf64_Addr min_alloc, max_alloc;   // Min. and max. aligned allocables

	Elf64_Addr dyn_addr = 0x0000000000000000;

	// Get to the PHT
	image_seek(elf_hdr->e_phoff, module);

	// Load the PHT
	pht = malloc(elf_hdr->e_phnum * elf_hdr->e_phentsize);
	if (!pht)
		return -1;

	image_read(pht, elf_hdr->e_phnum * elf_hdr->e_phentsize, module);

	// Compute the memory needings of the module
	for (i=0; i < elf_hdr->e_phnum; i++) {
		cr_pht = (Elf64_Phdr*)(pht + i * elf_hdr->e_phentsize);

		switch (cr_pht->p_type) {
		case PT_LOAD:
			if (i == 0) {
				min_addr = cr_pht->p_vaddr;
			} else {
				min_addr = MIN(min_addr, cr_pht->p_vaddr);
			}

			max_addr = MAX(max_addr, cr_pht->p_vaddr + cr_pht->p_memsz);
			max_align = MAX(max_align, cr_pht->p_align);
			break;
		case PT_DYNAMIC:
			dyn_addr = cr_pht->p_vaddr;
			break;
		default:
			// Unsupported - ignore
			break;
		}
	}

	if (max_addr - min_addr == 0) {
		// No loadable segments
		DBG_PRINT("No loadable segments found\n");
		goto out;
	}

	if (dyn_addr == 0) {
		DBG_PRINT("No dynamic information segment found\n");
		goto out;
	}

	// The minimum address that should be allocated
	min_alloc = min_addr - (min_addr % max_align);

	// The maximum address that should be allocated
	max_alloc = max_addr - (max_addr % max_align);
	if (max_addr % max_align > 0)
		max_alloc += max_align;


	if (elf_malloc(&module->module_addr,
			max_align,
			max_alloc-min_alloc) != 0) {

		DBG_PRINT("Could not allocate segments\n");
		goto out;
	}

	module->base_addr = (Elf64_Addr)(module->module_addr) - min_alloc;
	module->module_size = max_alloc - min_alloc;

	// Zero-initialize the memory
	memset(module->module_addr, 0, module->module_size);

	for (i = 0; i < elf_hdr->e_phnum; i++) {
		cr_pht = (Elf64_Phdr*)(pht + i * elf_hdr->e_phentsize);

		if (cr_pht->p_type == PT_LOAD) {
			// Copy the segment at its destination
			if (cr_pht->p_offset < module->u.l._cr_offset) {
				// The segment contains data before the current offset
				// It can be discarded without worry - it would contain only
				// headers
				Elf64_Off aux_off = module->u.l._cr_offset - cr_pht->p_offset;

				if (image_read((char *)module_get_absolute(cr_pht->p_vaddr, module) + aux_off,
					       cr_pht->p_filesz - aux_off, module) < 0) {
					res = -1;
					goto out;
				}
			} else {
				if (image_seek(cr_pht->p_offset, module) < 0) {
					res = -1;
					goto out;
				}

				if (image_read(module_get_absolute(cr_pht->p_vaddr, module),
						cr_pht->p_filesz, module) < 0) {
					res = -1;
					goto out;
				}
			}

			/*
			DBG_PRINT("Loadable segment of size 0x%08x copied from vaddr 0x%08x at 0x%08x\n",
					cr_pht->p_filesz,
					cr_pht->p_vaddr,
					(Elf64_Addr)module_get_absolute(cr_pht->p_vaddr, module));
			*/
		}
	}

	// Get to the SHT
	image_seek(elf_hdr->e_shoff, module);

	// Load the SHT
	sht = malloc(elf_hdr->e_shnum * elf_hdr->e_shentsize);
	if (!sht) {
		res = -1;
		goto out;
	}

	image_read(sht, elf_hdr->e_shnum * elf_hdr->e_shentsize, module);

	// Setup the symtable size
	for (i = 0; i < elf_hdr->e_shnum; i++) {
		cr_sht = (Elf64_Shdr*)(sht + i * elf_hdr->e_shentsize);

		if (cr_sht->sh_type == SHT_DYNSYM) {
			module->symtable_size = cr_sht->sh_size;
			break;
		}
	}

	free(sht);

	// Setup dynamic segment location
	module->dyn_table = module_get_absolute(dyn_addr, module);

	/*
	DBG_PRINT("Base address: 0x%08x, aligned at 0x%08x\n", module->base_addr,
			max_align);
	DBG_PRINT("Module size: 0x%08x\n", module->module_size);
	*/

out:
	// Free up allocated memory
	if (pht != NULL)
		free(pht);

	return res;
}

int perform_relocation(struct elf_module *module, Elf_Rel *rel) {
	Elf64_Xword *dest = module_get_absolute(rel->r_offset, module);

	// The symbol reference index
	Elf64_Word sym = ELF64_R_SYM(rel->r_info);
	unsigned char type = ELF64_R_TYPE(rel->r_info);

	// The symbol definition (if applicable)
	Elf64_Sym *sym_def = NULL;
	struct elf_module *sym_module = NULL;
	Elf64_Addr sym_addr = 0x0;

	if (sym > 0) {
		// Find out details about the symbol

		// The symbol reference
		Elf64_Sym *sym_ref = symbol_get_entry(module, sym);

		// The symbol definition
		sym_def =
			global_find_symbol(module->str_table + sym_ref->st_name,
					&sym_module);

		if (sym_def == NULL) {
			DBG_PRINT("Cannot perform relocation for symbol %s\n",
					module->str_table + sym_ref->st_name);

			if (ELF64_ST_BIND(sym_ref->st_info) != STB_WEAK)
				return -1;

			// This must be a derivative-specific
			// function. We're OK as long as we never
			// execute the function.
			sym_def = global_find_symbol("undefined_symbol", &sym_module);
		}

		// Compute the absolute symbol virtual address
		sym_addr = (Elf64_Addr)module_get_absolute(sym_def->st_value, sym_module);

		if (sym_module != module) {
			// Create a dependency
			enforce_dependency(sym_module, module);
		}
	}

	switch (type) {
	case R_X86_64_NONE:
		// Do nothing
		break;
	case R_X86_64_64:
		*dest += sym_addr;
		break;
	case R_X86_64_PC32:
		*dest += sym_addr - (Elf32_Addr)dest;
		break;
	case R_X86_64_COPY:
		if (sym_addr > 0) {
			memcpy((void*)dest, (void*)sym_addr, sym_def->st_size);
		}
		break;
	case R_X86_64_GLOB_DAT:
	case R_X86_64_JUMP_SLOT:
		 //Maybe TODO: Keep track of the GOT entries allocations
		*dest = sym_addr;
		break;
	case R_X86_64_RELATIVE:
		*dest += module->base_addr;
		break;
	default:
		DBG_PRINT("Relocation type %d not supported\n", type);
		return -1;
	}

	return 0;
}

int resolve_symbols(struct elf_module *module) {
	Elf64_Dyn  *dyn_entry = module->dyn_table;
	unsigned int i;
	int res;

	Elf64_Word plt_rel_size = 0;
	void *plt_rel = NULL;

	void *rel = NULL;
	Elf64_Word rel_size = 0;
	Elf64_Word rel_entry = 0;
	Elf64_Xword rela_size = 0;
	Elf64_Xword rela_entry = 0;
	Elf64_Xword sym_ent = 0;

	// The current relocation
	Elf64_Rel *crt_rel;

	while (dyn_entry->d_tag != DT_NULL) {
		switch(dyn_entry->d_tag) {

		// PLT relocation information
		case DT_PLTRELSZ:
			plt_rel_size = dyn_entry->d_un.d_val;
			break;
		case DT_PLTREL:
			if (dyn_entry->d_un.d_val != DT_REL && dyn_entry->d_un.d_val != DT_RELA) {
				DBG_PRINT("Unsupported PLT relocation\n");
				return -1;
			}
			//break;
		case DT_JMPREL:
			plt_rel = module_get_absolute(dyn_entry->d_un.d_ptr, module);
			break;

		// Standard relocation information
		case DT_REL:
			rel = module_get_absolute(dyn_entry->d_un.d_ptr, module);
			break;
		case DT_RELA:
			rel = module_get_absolute(dyn_entry->d_un.d_ptr, module);
			break;
		case DT_RELSZ:
			rel_size = dyn_entry->d_un.d_val;
			break;
		case DT_RELASZ:
			rela_size = dyn_entry->d_un.d_val;
			break;
		case DT_RELENT:
			rel_entry = dyn_entry->d_un.d_val;
			break;
		case DT_RELAENT:
			rela_entry = dyn_entry->d_un.d_val;
			break;
		/* FIXME: We may need to rely upon SYMENT if DT_RELAENT is missing in the object file */
		case DT_SYMENT:
			sym_ent = dyn_entry->d_un.d_val;
			break;

		// Module initialization and termination
		case DT_INIT:
			// TODO Implement initialization functions
			break;
		case DT_FINI:
			// TODO Implement finalization functions
			break;
		}

		dyn_entry++;
	}

	if (rel_size > 0) {
		// Process standard relocations
		for (i = 0; i < rel_size/rel_entry; i++) {
			crt_rel = (Elf64_Rel*)(rel + i*rel_entry);

			res = perform_relocation(module, crt_rel);

			if (res < 0)
				return res;
		}

	}

	if (rela_size > 0) {
		// Process standard relocations
		for (i = 0; i < rela_size/rela_entry; i++) {
			crt_rel = (Elf64_Rel*)(rel + i*rela_entry);

			res = perform_relocation(module, crt_rel);

			if (res < 0)
				return res;
		}
	}
	if (plt_rel_size > 0) {
		// TODO: Permit this lazily
		// Process PLT relocations
		/* some modules do not have DT_SYMENT, set it sym_ent in such cases */
		if (!rela_entry) rela_entry = sym_ent; 
		//for (i = 0; i < plt_rel_size/sizeof(Elf64_Rel); i++) {
		for (i = 0; i < plt_rel_size/rela_entry; i++) {
			//crt_rel = (Elf64_Rel*)(plt_rel + i*sizeof(Elf64_Rel));
			crt_rel = (Elf64_Rel*)(plt_rel + i*rela_entry);

			res = perform_relocation(module, crt_rel);

			if (res < 0)
				return res;
		}
	}

	return 0;
}
