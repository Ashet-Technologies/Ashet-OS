#include <linux/list.h>
#include <sys/times.h>
#include <fcntl.h>
#include <stdbool.h>
#include <string.h>
#include <core.h>
#include <fs.h>
#include "cli.h"
#include "console.h"
#include "com32.h"
#include "menu.h"
#include "config.h"
#include "syslinux/adv.h"
#include "syslinux/boot.h"
#include "syslinux/config.h"

#include <sys/module.h>

struct file_ext {
	const char *name;
	enum kernel_type type;
};

static const struct file_ext file_extensions[] = {
	{ ".c32", IMAGE_TYPE_COM32 },
	{ ".img", IMAGE_TYPE_FDIMAGE },
	{ ".bss", IMAGE_TYPE_BSS },
	{ ".bin", IMAGE_TYPE_BOOT },
	{ ".bs", IMAGE_TYPE_BOOT },
	{ ".0", IMAGE_TYPE_PXE },
	{ NULL, 0 },
};

/*
 * Return a pointer to one byte after the last character of the
 * command.
 */
static inline const char *find_command(const char *str)
{
	const char *p;

	p = str;
	while (*p && !my_isspace(*p))
		p++;
	return p;
}

__export uint32_t parse_image_type(const char *kernel)
{
	const struct file_ext *ext;
	const char *p;
	int len;

	/* Find the end of the command */
	p = find_command(kernel);
	len = p - kernel;

	for (ext = file_extensions; ext->name; ext++) {
		int elen = strlen(ext->name);

		if (!strncmp(kernel + len - elen, ext->name, elen))
			return ext->type;
	}

	/* use IMAGE_TYPE_KERNEL as default */
	return IMAGE_TYPE_KERNEL;
}

/*
 * Returns the kernel name with file extension if one wasn't present.
 */
static const char *get_extension(const char *kernel)
{
	const struct file_ext *ext;
	const char *p;
	int len;

	/* Find the end of the command */
	p = find_command(kernel);
	len = p - kernel;

	for (ext = file_extensions; ext->name; ext++) {
		char *str;
		int elen = strlen(ext->name);
		FILE *f;

		str = malloc(len + elen + 1);

		strncpy(str, kernel, len);
		strncpy(str + len, ext->name, elen);
		str[len + elen] = '\0';
		f = findpath(str);
		free(str);

		if (f) {
			fclose(f);
			return ext->name;
		}
	}

	return NULL;
}

const char *apply_extension(const char *kernel, const char *ext)
{
	const char *p;
	char *k;
	int len = strlen(kernel);
	int elen = strlen(ext);

	k = malloc(len + elen + 1);
	if (!k)
		return NULL;

	p = find_command(kernel);

	len = p - kernel;

	/* Copy just the kernel name */
	memcpy(k, kernel, len);

	/* Append the extension */
	if (strncmp(p - elen, ext, elen)) {
		memcpy(k + len, ext, elen);
		len += elen;
	}

	/* Copy the rest of the command line */
	strcpy(k + len, p);

	k[len + strlen(p)] = '\0';

	return k;
}

/*
 * Attempt to load a kernel after deciding what type of image it is.
 *
 * We only return from this function if something went wrong loading
 * the the kernel. If we return the caller should call enter_cmdline()
 * so that the user can help us out.
 */
__export void load_kernel(const char *command_line)
{
	struct menu_entry *me;
	const char *cmdline;
	const char *kernel;
	uint32_t type;

	kernel = strdup(command_line);
	if (!kernel)
		goto bad_kernel;

	/* Virtual kernel? */
	me = find_label(kernel);
	if (me) {
		const char *args;
		char *cmd;
		size_t len = strlen(me->cmdline) + 1;

		/* Find the end of the command */
		args = find_command(kernel);
		while(*args && my_isspace(*args))
			args++;

		if (strlen(args))
			len += strlen(args) + 1; /* +1 for space (' ') */

		cmd = malloc(len);
		if (!cmd)
			goto bad_kernel;

		if (strlen(args))
			snprintf(cmd, len, "%s %s", me->cmdline, args);
		else
			strncpy(cmd, me->cmdline, len);

		type = parse_image_type(cmd);
		execute(cmd, type, false);
		/* We shouldn't return */
		goto bad_kernel;
	}

	if (!allowimplicit)
		goto bad_implicit;

	/* Insert a null character to ignore any user-specified options */
	if (!allowoptions) {
		char *p = (char *)find_command(kernel);
		*p = '\0';
	}

	type = parse_image_type(kernel);
	if (type == IMAGE_TYPE_KERNEL) {
		const char *ext;

		/*
		 * Automatically lookup the extension if one wasn't
		 * supplied by the user.
		 */
		ext = get_extension(kernel);
		if (ext) {
			const char *k;

			k = apply_extension(kernel, ext);
			if (!k)
				goto bad_kernel;

			free((void *)kernel);
			kernel = k;

			type = parse_image_type(kernel);
		}
	}

	execute(kernel, type, true);
	free((void *)kernel);

bad_implicit:
bad_kernel:
	/*
	 * If we fail to boot the kernel execute the "onerror" command
	 * line.
	 */
	if (onerrorlen) {
		me = find_label(onerror);
		if (me)
			rsprintf(&cmdline, "%s %s", me->cmdline, default_cmd);
		else
			rsprintf(&cmdline, "%s %s", onerror, default_cmd);

		type = parse_image_type(cmdline);
		execute(cmdline, type, true);
	}
}

/*
 * If this function returns you must call ldinux_enter_command() to
 * preserve the 4.0x behaviour.
 */
void ldlinux_auto_boot(void)
{
	if (!defaultlevel) {
		if (strlen(ConfigName))
			printf("No DEFAULT or UI configuration directive found!\n");
		if (noescape)
			kaboom();
	} else
		load_kernel(default_cmd);
}

static void enter_cmdline(void)
{
	const char *cmdline;

	/* Enter endless command line prompt, should support "exit" */
	while (1) {
		bool to = false;

		if (noescape) {
			ldlinux_auto_boot();
			continue;
		}

		cmdline = edit_cmdline("boot:", 1, NULL, cat_help_file, &to);
		printf("\n");

		/* return if user only press enter or we timed out */
		if (!cmdline || cmdline[0] == '\0') {
			if (to && ontimeoutlen)
				load_kernel(ontimeout);
			else
				ldlinux_auto_boot();
		} else
			load_kernel(cmdline);
	}
}

void ldlinux_enter_command(void)
{
	enter_cmdline();
}

/*
 * Undo the work we did in openconsole().
 */
static void __destructor close_console(void)
{
	int i;

	for (i = 0; i <= 2; i++)
		close(i);
}

void ldlinux_console_init(void)
{
	openconsole(&dev_stdcon_r, &dev_ansiserial_w);
}

__export int main(int argc __unused, char **argv)
{
	const void *adv;
	const char *cmdline;
	size_t count = 0;

	ldlinux_console_init();

	parse_configs(&argv[1]);

	__syslinux_set_serial_console_info();

	adv = syslinux_getadv(ADV_BOOTONCE, &count);
	if (adv && count) {
		/*
		 * We apparently have a boot-once set; clear it and
		 * then execute the boot-once.
		 */
		char *src, *dst;
		size_t i;

		src = (char *)adv;
		cmdline = dst = malloc(count + 1);
		if (!dst) {
			printf("Failed to allocate memory for ADV\n");
			ldlinux_enter_command();
		}

		for (i = 0; i < count; i++)
			*dst++ = *src++;
		*dst = '\0';	/* Null-terminate */

		/* Clear the boot-once data from the ADV */
		if (!syslinux_setadv(ADV_BOOTONCE, 0, NULL))
			syslinux_adv_write();

		load_kernel(cmdline); /* Shouldn't return */
		ldlinux_enter_command();
	}

	if (!forceprompt && !shift_is_held())
		ldlinux_auto_boot();

	if (defaultlevel > 1)
		ldlinux_auto_boot();

	ldlinux_enter_command();
	return 0;
}
