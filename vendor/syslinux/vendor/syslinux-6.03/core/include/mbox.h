/*
 * mbox.h
 *
 * Simple thread mailbox interface
 */

#ifndef _MBOX_H
#define _MBOX_H

#include "thread.h"

/*
 * If a mailbox is allocated statically (as a struct mailbox), this
 * is the number of slots it gets.
 */
#define MAILBOX_STATIC_SIZE	512

struct mailbox {
    struct semaphore prod_sem;	/* Producer semaphore (empty slots) */
    struct semaphore cons_sem;	/* Consumer semaphore (data slots) */
    struct semaphore head_sem;	/* Head pointer semaphore */
    struct semaphore tail_sem;	/* Tail pointer semaphore */
    void **wrap;		/* Where pointers wrap */
    void **head;		/* Head pointer */
    void **tail;		/* Tail pointer */

    void *data[MAILBOX_STATIC_SIZE]; /* Data array */
};

/* The number of bytes for an mailbox of size s */
#define MBOX_BYTES(s) (sizeof(struct mailbox) + \
		       ((s)-MAILBOX_STATIC_SIZE)*sizeof(void *))

void mbox_init(struct mailbox *mbox, size_t size);
int mbox_post(struct mailbox *mbox, void *msg, mstime_t timeout);
mstime_t mbox_fetch(struct mailbox *mbox, void **msg, mstime_t timeout);

/*
 * This marks a mailbox object as unusable; it will remain unusable
 * until sem_init() is called on it again.  This DOES NOT clear the
 * list of blocked processes on this mailbox!
 *
 * It is also possible to mark the mailbox invalid by zeroing its
 * memory structure.
 */
static inline void mbox_set_invalid(struct mailbox *mbox)
{
    if (!!mbox)
	sem_set_invalid(&mbox->prod_sem);
}

/*
 * Ask if a mailbox object has been initialized.
 */
static inline bool mbox_is_valid(struct mailbox *mbox)
{
    return ((!!mbox) && sem_is_valid(&mbox->prod_sem));
}

#endif /* _MBOX_H */
