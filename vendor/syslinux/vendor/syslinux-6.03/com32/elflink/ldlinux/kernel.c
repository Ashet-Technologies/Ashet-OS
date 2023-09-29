#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <console.h>
#include <dprintf.h>
#include <syslinux/loadfile.h>
#include <syslinux/linux.h>
#include <syslinux/pxe.h>
#include "core.h"

const char *globaldefault = NULL;
const char *append = NULL;

/* Will be called from readconfig.c */
int new_linux_kernel(char *okernel, char *ocmdline)
{
	const char *kernel_name = NULL, *args = NULL;
	struct initramfs *initramfs = NULL;
	char *temp;
	void *kernel_data;
	size_t kernel_len, cmdline_len;
	bool opt_quiet = false;
	char *initrd_name, *cmdline;

	dprintf("okernel = %s, ocmdline = %s", okernel, ocmdline);

	if (okernel)
		kernel_name = okernel;
	else if (globaldefault)
		kernel_name = globaldefault;

	if (ocmdline)
		args = ocmdline;
	else if (append)
		args = append;

	cmdline_len = strlen("BOOT_IMAGE=") + strlen(kernel_name);
	cmdline_len += 1;	/* space between BOOT_IMAGE and args */
	cmdline_len += strlen(args);
	cmdline_len += 1;	/* NUL-termination */

	cmdline = malloc(cmdline_len);
	if (!cmdline) {
	    printf("Failed to alloc memory for cmdline\n");
	    return 1;
	}

	sprintf(cmdline, "BOOT_IMAGE=%s %s", kernel_name, args);

	/* "keeppxe" handling */
#if IS_PXELINUX
	extern char KeepPXE;

	if (strstr(cmdline, "keeppxe"))
		KeepPXE |= 1;
#endif

	if (strstr(cmdline, "quiet"))
		opt_quiet = true;

	if (!opt_quiet)
		printf("Loading %s... ", kernel_name);

	if (loadfile(kernel_name, &kernel_data, &kernel_len)) {
		if (opt_quiet)
			printf("Loading %s ", kernel_name);
		printf("failed: ");
		goto bail;
	}

	if (!opt_quiet)
		printf("ok\n");

	/* Find and load initramfs */
	temp = strstr(cmdline, "initrd=");
	if (temp) {
		/* Initialize the initramfs chain */
		initramfs = initramfs_init();
		if (!initramfs)
			goto bail;

		temp += 6; /* strlen("initrd") */
		do {
		    size_t n = 0;
		    char *p;

		    temp++;	/* Skip = or , */

		    p = temp;
		    while (*p != ' ' && *p != ',' && *p) {
			p++;
			n++;
		    }

		    initrd_name = malloc(n + 1);
		    if (!initrd_name) {
			printf("Failed to allocate space for initrd\n");
			goto bail;
		    }

		    snprintf(initrd_name, n + 1, "%s", temp);
		    temp += n;

		    if (!opt_quiet)
			printf("Loading %s...", initrd_name);

		    if (initramfs_load_archive(initramfs, initrd_name)) {
			if (opt_quiet)
			    printf("Loading %s ", initrd_name);
			free(initrd_name);
			printf("failed: ");
			goto bail;
		    }

		    free(initrd_name);

		    if (!opt_quiet)
			printf("ok\n");
		} while (*temp == ',');
	}

	/* This should not return... */
	syslinux_boot_linux(kernel_data, kernel_len, initramfs, NULL, cmdline);
	printf("Booting kernel failed: ");

bail:
	free(cmdline);
	printf("%s\n", strerror(errno));
	return 1;
}
