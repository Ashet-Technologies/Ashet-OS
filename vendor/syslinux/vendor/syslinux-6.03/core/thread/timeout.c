/*
 * timeout.c
 *
 */

#include "thread.h"

/*
 * __thread_process_timeouts()
 *
 * Look for threads that have timed out.  This should be called
 * under interrupt lock, before calling __schedule().
 */
void __thread_process_timeouts(void)
{
    struct thread *curr = current();
    struct thread_list *tp;
    struct thread *t;
    mstime_t now = ms_timer();
    struct thread_block *block;
    mstime_t timeout;

    /* The current thread is obviously running, so no need to check... */
    for (tp = curr->list.next; tp != &curr->list; tp = tp->next) {
	t = container_of(tp, struct thread, list);
	if ((block = t->blocked) && (timeout = block->timeout)) {
	    if ((mstimediff_t)(timeout - now) <= 0) {
		struct semaphore *sem = block->semaphore;
		/* Remove us from the queue and increase the count */
		block->list.next->prev = block->list.prev;
		block->list.prev->next = block->list.next;
		sem->count++;

		t->blocked = NULL;
		block->timed_out = true;

		__schedule();	/* Normally sets just __need_schedule */
	    }
	}
    }
}
