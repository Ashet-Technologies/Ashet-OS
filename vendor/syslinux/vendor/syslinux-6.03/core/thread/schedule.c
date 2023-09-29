#include <klibc/compiler.h>
#include <sys/cpu.h>
#include "thread.h"
#include "core.h"
#include <dprintf.h>

void (*sched_hook_func)(void);

/*
 * __schedule() should only be called with interrupts locked out!
 */
void __schedule(void)
{
    static bool in_sched_hook;
    struct thread *curr = current();
    struct thread *st, *nt, *best;

#if DEBUG
    if (__unlikely(irq_state() & 0x200)) {
	dprintf("In __schedule with interrupts on!\n");
	kaboom();
    }
#endif

    /*
     * Are we called from inside sched_hook_func()?  If so we'll
     * schedule anyway on the way out.
     */
    if (in_sched_hook)
	return;

    dprintf("Schedule ");

    /* Possibly update the information on which we make
     * scheduling decisions.
     */
    if (sched_hook_func) {
	in_sched_hook = true;
	sched_hook_func();
	in_sched_hook = false;
    }

    /*
     * The unusual form of this walk is because we have to start with
     * the thread *following* curr, and curr may not actually be part
     * of the list anymore (in the case of __exit_thread).
     */
    best = NULL;
    nt = st = container_of(curr->list.next, struct thread, list);
    do {
	if (__unlikely(nt->thread_magic != THREAD_MAGIC)) {
	    dprintf("Invalid thread on thread list %p magic = 0x%08x\n",
		    nt, nt->thread_magic);
	    kaboom();
	}

	dprintf("Thread %p (%s) ", nt, nt->name);
	if (!nt->blocked) {
	    dprintf("runnable priority %d\n", nt->prio);
	    if (!best || nt->prio < best->prio)
		best = nt;
	} else {
	    dprintf("blocked\n");
	}
	nt = container_of(nt->list.next, struct thread, list);
    } while (nt != st);

    if (!best)
	kaboom();		/* No runnable thread */

    if (best != curr) {
	uint64_t tsc;
	
	asm volatile("rdtsc" : "=A" (tsc));
	
	dprintf("@ %llu -> %p (%s)\n", tsc, best, best->name);
	__switch_to(best);
    } else {
	dprintf("no change\n");
    }
}

/*
 * This can be called from "normal" code...
 */
void thread_yield(void)
{
    irq_state_t irq = irq_save();
    __schedule();
    irq_restore(irq);
}
