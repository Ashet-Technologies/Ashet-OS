#include "arch/sys_arch.h"
#include "lwip/sys.h"
#include "lwip/mem.h"
#include <stdlib.h>
#include <thread.h>

void sys_init(void)
{
}

err_t sys_sem_new(sys_sem_t *sem, u8_t count)
{
    if (!sem)
	return EINVAL;
    *sem = malloc(sizeof(struct semaphore));
    if (!*sem)
	return ENOMEM;

    sem_init(*sem, count);
    return 0;
}

void sys_sem_free(sys_sem_t *sem)
{
    if (!!sem && !!*sem) {
	sys_sem_set_invalid(sem);
	free(*sem);
	*sem = NULL;
    }
}

void sys_sem_set_invalid(sys_sem_t *sem)
{
    if (!sem || !*sem)
	return;
    sem_set_invalid(*sem);
}


int sys_sem_valid(sys_sem_t *sem)
{
    if (!sem || !*sem)
	return 0;
    return sem_is_valid(*sem);
}

u32_t sys_arch_sem_wait(sys_sem_t *sem, u32_t timeout)
{
    mstime_t rv;

    if (!sem || !*sem)
	return SYS_ARCH_TIMEOUT;
    rv = sem_down(*sem, timeout);
    if (rv == (mstime_t)-1)
	return SYS_ARCH_TIMEOUT;
    else
	return rv;
}

err_t sys_mbox_new(sys_mbox_t *mbox, int size)
{
    if (!mbox)
	return EINVAL;
    *mbox = malloc(MBOX_BYTES(size));
    if (!(*mbox))
	return ENOMEM;

    mbox_init(*mbox, size);
    return 0;
}

void sys_mbox_free(sys_mbox_t *mbox)
{
    if (!!mbox && !!*mbox) {
	sys_mbox_set_invalid(mbox);
	free(*mbox);
	*mbox = NULL;
    }
}

void sys_mbox_post(sys_mbox_t *mbox, void *msg)
{
    if (!!mbox)
	mbox_post(*mbox, msg, 0);
}

err_t sys_mbox_trypost(sys_mbox_t *mbox, void *msg)
{
    if (!mbox)
	return EINVAL;
    return mbox_post(*mbox, msg, -1);
}

u32_t sys_arch_mbox_fetch(sys_mbox_t *mbox, void **msg, u32_t timeout)
{
    mstime_t rv;

    if (!mbox)
	return SYS_MBOX_EMPTY;
    rv = mbox_fetch(*mbox, msg, timeout);
    if (rv == (mstime_t)-1)
	return SYS_ARCH_TIMEOUT;
    else
	return rv;
}

u32_t sys_arch_mbox_tryfetch(sys_mbox_t *mbox, void **msg)
{
    if (!mbox)
	return SYS_MBOX_EMPTY;
    return mbox_fetch(*mbox, msg, -1);
}

void sys_mbox_set_invalid(sys_mbox_t *mbox)
{
    if (!!mbox)
	mbox_set_invalid(*mbox);
}

int sys_mbox_valid(sys_mbox_t *mbox)
{
    return ((!!mbox) && mbox_is_valid(*mbox));
}


sys_thread_t sys_thread_new(const char *name, lwip_thread_fn thread,
			    void *arg, int stacksize, int prio)
{
    return start_thread(name, stacksize, prio, thread, arg);
}

