/*
 * exec.c
 *
 *  Created on: Aug 14, 2008
 *      Author: Stefan Bucur <stefanb@zytor.com>
 */

#include <sys/module.h>
#include <sys/exec.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <setjmp.h>
#include <setjmp.h>
#include <alloca.h>
#include <dprintf.h>

#define DBG_PRINT(fmt, args...) dprintf("[EXEC] " fmt, ##args)

struct elf_module *__syslinux_current = NULL;

int get_module_type(struct elf_module *module)
{
	if(module->main_func) return EXEC_MODULE;
	return LIB_MODULE;
}

jmp_buf __process_exit_jmp;

#if 0
int spawnv(const char *name, const char **argv)
{
	int res, ret_val = 0;
	const char **arg;
	int argc;
	char **argp, **args;
	struct elf_module *previous;
	malloc_tag_t prev_mem_tag;

	struct elf_module *module = module_alloc(name);

	if (module == NULL)
		return -1;

	res = module_load(module);
	if (res != 0) {
		module_unload(module);
		return res;
	}

	if (module->main_func == NULL) {
		// We can't execute without a main function
		module_unload(module);
		return -1;
	}
	/*if (module->main_func != NULL) {
		const char **last_arg = argv;
		void *old_tag;
		while (*last_arg != NULL)
			last_arg++;

		// Setup the memory allocation context
		old_tag = __mem_get_tag_global();
		__mem_set_tag_global(module);

		// Execute the program
		ret_val = (*(module->main_func))(last_arg - argv, argv);

		// Clean up the allocation context
		__free_tagged(module);
		// Restore the allocation context
		__mem_set_tag_global(old_tag);
	} else {
		// We can't execute without a main function
		module_unload(module);
		return -1;
	}*/
	// Set up the process context
	previous = __syslinux_current;
	prev_mem_tag = __mem_get_tag_global();

	// Setup the new process context
	__syslinux_current = module;
	__mem_set_tag_global((malloc_tag_t)module);

	// Generate a new process copy of argv (on the stack)
	argc = 0;
	for (arg = argv; *arg; arg++)
		argc++;

	args = alloca((argc+1) * sizeof(char *));

	for (arg = argv, argp = args; *arg; arg++, argp++) {
		size_t l = strlen(*arg)+1;
		*argp = alloca(l);
		memcpy(*argp, *arg, l);
	}

	*args = NULL;

	// Execute the program
	ret_val = setjmp(module->u.x.process_exit);

	if (ret_val)
		ret_val--;		/* Valid range is 0-255 */
	else if (!module->main_func)
		ret_val = -1;
	else
		exit((module->main_func)(argc, args)); /* Actually run! */

	// Clean up the allocation context
	__free_tagged(module);
	// Restore the allocation context
	__mem_set_tag_global(prev_mem_tag);
	// Restore the process context
	__syslinux_current = previous;

	res = module_unload(module);

	if (res != 0) {
		return res;
	}

	return ((unsigned int)ret_val & 0xFF);
}

int spawnl(const char *name, const char *arg, ...)
{
	/*
	 * NOTE: We assume the standard ABI specification for the i386
	 * architecture. This code may not work if used in other
	 * circumstances, including non-variadic functions, different
	 * architectures and calling conventions.
	 */
	return spawnv(name, &arg);
}
#endif

/*
 * Load a module and runs its start function.
 *
 * For library modules the start function is module->init_func and for
 * executable modules its module->main_func.
 *
 * "name" is the name of the module to load.
 *
 * "argv" and "argc" are only passed to module->main_func, for library
 * modules these arguments can be NULL and 0, respectively.
 *
 * "argv" is an array of arguments to pass to module->main_func.
 * argv[0] must be a pointer to "name" and argv[argc] must be NULL.
 *
 * "argc" is the number of arguments in "argv".
 */
int spawn_load(const char *name, int argc, char **argv)
{
	int res, ret_val = 0;
	struct elf_module *previous;
	//malloc_tag_t prev_mem_tag;
	struct elf_module *module = module_alloc(name);
	struct elf_module *cur_module;
	int type;

	dprintf("enter: name = %s", name);

	if (module == NULL)
		return -1;

	if (get_module_type(module) == EXEC_MODULE) {
		if (!argc || !argv || strcmp(argv[0], name)) {
			dprintf("invalid args for %s\n", name);
			res = -1;
			goto out;
		}
	}

	cur_module = module_current();
	if (!strcmp(cur_module->name, module->name)) {
		dprintf("We is running this module %s already!", module->name);

		module_unload(cur_module);
	}

	res = module_load(module);
	if (res != 0) {
		dprintf("failed to load module %s\n", module->name);
		goto out;
	}

	type = get_module_type(module);

	dprintf("type = %d, prev = %s, cur = %s",
		type, cur_module->name, module->name);

	if(type==EXEC_MODULE)
	{
		previous = __syslinux_current;
		//prev_mem_tag = __mem_get_tag_global();

		// Setup the new process context
		__syslinux_current = module;
		//__mem_set_tag_global((malloc_tag_t)module);

		// Execute the program
		ret_val = setjmp(module->u.x.process_exit);

		if (ret_val)
			ret_val--;		/* Valid range is 0-255 */
		else if (!module->main_func)
			ret_val = -1;
		else
			exit((module->main_func)(argc, argv)); /* Actually run! */

		// Clean up the allocation context
		//__free_tagged(module);
		// Restore the allocation context
		//__mem_set_tag_global(prev_mem_tag);
		// Restore the process context
		__syslinux_current = previous;

		res = module_unload(module);

		if (res != 0)
			goto out;
	}

out:
	if (res)
		_module_unload(module);
	return res;
}

void exec_term(void)
{
	modules_term();
}
