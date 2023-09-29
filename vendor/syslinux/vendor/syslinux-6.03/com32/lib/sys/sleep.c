/*
 * sys/sleep.c
 */

#include <unistd.h>
#include <sys/times.h>
#include <syslinux/idle.h>

unsigned int msleep(unsigned int msec)
{
    clock_t start = times(NULL);

    while (times(NULL) - start < msec)
	syslinux_idle();

    return 0;
}

unsigned int sleep(unsigned int seconds)
{
    return msleep(seconds * 1000);
}
