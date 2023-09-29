#include <syslinux/boot.h>
#include <stdlib.h>

int main(int argc, char *argv[])
{
    syslinux_local_boot(argc > 1 ? atoi(argv[1]) : 0);

    return 0;
}
