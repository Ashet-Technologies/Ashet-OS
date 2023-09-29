#include <core.h>
#include <com32.h>
#include <sys/io.h>
#include <fs.h>
#include <bios.h>
#include <syslinux/memscan.h>
#include <syslinux/firmware.h>

void init(void)
{
	firmware->init();
}
