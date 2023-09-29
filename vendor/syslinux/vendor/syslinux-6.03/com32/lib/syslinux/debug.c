#include <linux/list.h>
#include <string.h>
#include <stdbool.h>

#ifdef DYNAMIC_DEBUG

static LIST_HEAD(debug_funcs);

struct debug_func_entry {
    const char *name;
    struct list_head list;
};

static struct debug_func_entry *lookup_entry(const char *func)
{
    struct debug_func_entry *e, *entry = NULL;

    list_for_each_entry(e, &debug_funcs, list) {
	if (!strcmp(e->name, func)) {
	    entry = e;
	    break;
	}
    }

    return entry;
}

bool __syslinux_debug_enabled(const char *func)
{
    struct debug_func_entry *entry;

    entry = lookup_entry(func);
    if (entry)
	return true;

    return false;
}

static int __enable(const char *func)
{
    struct debug_func_entry *entry;

    entry = lookup_entry(func);
    if (entry)
	return 0;	/* already enabled */

    entry = malloc(sizeof(*entry));
    if (!entry)
	return -1;

    entry->name = func;
    list_add(&entry->list, &debug_funcs);
    return 0;
}

static int __disable(const char *func)
{
    struct debug_func_entry *entry;

    entry = lookup_entry(func);
    if (!entry)
	return 0;	/* already disabled */

    list_del(&entry->list);
    free(entry);
    return 0;
}

/*
 * Enable or disable debug code for function 'func'.
 */
int syslinux_debug(const char *func, bool enable)
{
    int rv;

    if (enable)
	rv = __enable(func);
    else
	rv = __disable(func);

    return rv;
}

#else

int syslinux_debug(const char *func, bool enable)
{
    (void)func;
    (void)enable;

    printf("Dynamic debug unavailable\n");
    return -1;
}

#endif /* DYNAMIC_DEBUG */
