#ifndef _THREAD_H
#define _THREAD_H

#include <stddef.h>
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <timer.h>
#include <sys/cpu.h>

/* The idle thread runs at this priority */
#define IDLE_THREAD_PRIORITY	INT_MAX

/* This priority should normally be used for hardware-polling threads */
#define POLL_THREAD_PRIORITY	(INT_MAX-1)

struct semaphore;

struct thread_list {
    struct thread_list *next, *prev;
};

/*
 * Stack frame used by __switch_to, see thread_asm.S
 */
struct thread_stack {
    int errno;
    uint16_t rmsp, rmss;
    uint32_t edi, esi, ebp, ebx;
    void (*eip)(void);
};

struct thread_block {
    struct thread_list list;
    struct thread *thread;
    struct semaphore *semaphore;
    mstime_t block_time;
    mstime_t timeout;
    bool timed_out;
};

#define THREAD_MAGIC 0x3568eb7d

struct thread {
    struct thread_stack *esp;	/* Must be first; stack pointer */
    unsigned int thread_magic;
    const char *name;		/* Name (for debugging) */
    struct thread_list  list;
    struct thread_block *blocked;
    void *stack, *rmstack;	/* Stacks, iff allocated by malloc/lmalloc */
    void *pvt; 			/* For the benefit of lwIP */
    int prio;
};

extern void (*sched_hook_func)(void);

void __thread_process_timeouts(void);
void __schedule(void);
void __switch_to(struct thread *);
void thread_yield(void);

extern struct thread *__current;
static inline struct thread *current(void)
{
    return __current;
}

struct semaphore {
    int count;
    struct thread_list list;
};

#define DECLARE_INIT_SEMAPHORE(sem, cnt)	\
    struct semaphore sem = {			\
	.count = (cnt),				\
	.list =	{				\
            .next = &sem.list,			\
            .prev = &sem.list                   \
        }					\
    }

mstime_t sem_down(struct semaphore *, mstime_t);
void sem_up(struct semaphore *);
void sem_init(struct semaphore *, int);

/*
 * This marks a semaphore object as unusable; it will remain unusable
 * until sem_init() is called on it again.  This DOES NOT clear the
 * list of blocked processes on this semaphore!
 *
 * It is also possible to mark the semaphore invalid by zeroing its
 * memory structure.
 */
static inline void sem_set_invalid(struct semaphore *sem)
{
    if (!!sem)
	sem->list.next = NULL;
}

/*
 * Ask if a semaphore object has been initialized.
 */
static inline bool sem_is_valid(struct semaphore *sem)
{
    return ((!!sem) && (!!sem->list.next));
}

struct thread *start_thread(const char *name, size_t stack_size, int prio,
			    void (*start_func)(void *), void *func_arg);
void __exit_thread(void);
void kill_thread(struct thread *);

void start_idle_thread(void);
void test_thread(void);

#endif /* _THREAD_H */
