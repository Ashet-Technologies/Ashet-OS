#include <unistd.h>
#include <core.h>

int generic_chdir_start(void)
{
	return chdir(CurrentDirName);
}
