#include <syslinux/reboot.h>
#include <string.h>

int main(int argc, char *argv[])
{
    int warm = 0;
    int i;

    for (i = 1; i < argc; i++) {
	if (!strcmp(argv[i], "-w") || !strcmp(argv[i], "--warm"))
	    warm = 1;
    }

    syslinux_reboot(warm);
}
