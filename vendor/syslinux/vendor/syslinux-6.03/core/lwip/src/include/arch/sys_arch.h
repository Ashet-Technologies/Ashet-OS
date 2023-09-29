#ifndef __LWIP_ARCH_SYS_ARCH_H__
#define __LWIP_ARCH_SYS_ARCH_H__

#include <stddef.h>
#include "arch/cc.h"
#include <thread.h>
#include <mbox.h>

typedef struct semaphore *sys_sem_t;
typedef struct mailbox   *sys_mbox_t;
typedef struct thread    *sys_thread_t;

static inline void sys_sem_signal(sys_sem_t *sem)
{
    if (!!sem)
	sem_up(*sem);
}

#define sys_now ms_timer

#define SYS_MBOX_NULL	NULL
#define SYS_SEM_NULL	NULL

extern void __compile_time_error(void);

#define SYS_ARCH_OP(var, val, inc, add)					\
do {									\
    if (__builtin_constant_p(val) && (val) == 1) {			\
	switch (sizeof(var)) {						\
	case 1:								\
	    asm volatile(inc "b %0" : "+m" (var));			\
	    break;							\
	case 2:								\
	    asm volatile(inc "w %0" : "+m" (var));			\
	    break;							\
	case 4:								\
	    asm volatile(inc "l %0" : "+m" (var));			\
	    break;							\
	default:							\
	    __compile_time_error();					\
	    break;							\
	}								\
    } else {								\
	switch (sizeof(var)) {						\
	case 1:								\
	    asm volatile(add "b %1,%0" : "+m" (var) : "ri" (val));	\
	    break;							\
	case 2:								\
	    asm volatile(add "w %1,%0" : "+m" (var) : "ri" (val));	\
	    break;							\
	case 4:								\
	    asm volatile(add "l %1,%0" : "+m" (var) : "ri" (val));	\
	    break;							\
	default:							\
	    __compile_time_error();					\
	    break;							\
	}								\
    }									\
} while (0)

static inline struct sys_timeouts *sys_arch_timeouts(void)
{
    return (struct sys_timeouts *)&current()->pvt;
}

#define SYS_ARCH_INC(var, val) SYS_ARCH_OP(var, val, "inc", "add")
#define SYS_ARCH_DEC(var, val) SYS_ARCH_OP(var, val, "dec", "sub")

#define SYS_ARCH_GET(var, ret)					\
    do {						 	\
        volatile __typeof__(var) * const __varp = &(var);	\
    	ret = *__varp;						\
    } while (0)

#define SYS_ARCH_SET(var, val)					\
    do {						 	\
        volatile __typeof__(var) * const __varp = &(var);	\
    	*__varp = val;						\
    } while (0)

#define SYS_ARCH_DECL_PROTECT(VAR) irq_state_t VAR
#define SYS_ARCH_PROTECT(VAR) VAR = irq_save()
#define SYS_ARCH_UNPROTECT(VAR) irq_restore(VAR)

#endif /* __LWIP_ARCH_SYS_ARCH_H__ */
