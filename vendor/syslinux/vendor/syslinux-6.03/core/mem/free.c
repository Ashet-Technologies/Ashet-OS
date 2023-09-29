/*
 * free.c
 *
 * Very simple linked-list based malloc()/free().
 */

#include <syslinux/firmware.h>
#include <stdlib.h>
#include <dprintf.h>
#include "malloc.h"

#include <stdio.h>

static struct free_arena_header *
__free_block(struct free_arena_header *ah)
{
    struct free_arena_header *pah, *nah;
    struct free_arena_header *head =
	&__core_malloc_head[ARENA_HEAP_GET(ah->a.attrs)];

    pah = ah->a.prev;
    nah = ah->a.next;
    if ( ARENA_TYPE_GET(pah->a.attrs) == ARENA_TYPE_FREE &&
           (char *)pah+ARENA_SIZE_GET(pah->a.attrs) == (char *)ah ) {
        /* Coalesce into the previous block */
        ARENA_SIZE_SET(pah->a.attrs, ARENA_SIZE_GET(pah->a.attrs) +
		ARENA_SIZE_GET(ah->a.attrs));
        pah->a.next = nah;
        nah->a.prev = pah;

#ifdef DEBUG_MALLOC
        ARENA_TYPE_SET(ah->a.attrs, ARENA_TYPE_DEAD);
#endif

        ah = pah;
        pah = ah->a.prev;
    } else {
        /* Need to add this block to the free chain */
        ARENA_TYPE_SET(ah->a.attrs, ARENA_TYPE_FREE);
        ah->a.tag = MALLOC_FREE;

        ah->next_free = head->next_free;
        ah->prev_free = head;
        head->next_free = ah;
        ah->next_free->prev_free = ah;
    }

    /* In either of the previous cases, we might be able to merge
       with the subsequent block... */
    if ( ARENA_TYPE_GET(nah->a.attrs) == ARENA_TYPE_FREE &&
           (char *)ah+ARENA_SIZE_GET(ah->a.attrs) == (char *)nah ) {
        ARENA_SIZE_SET(ah->a.attrs, ARENA_SIZE_GET(ah->a.attrs) +
		ARENA_SIZE_GET(nah->a.attrs));

        /* Remove the old block from the chains */
        nah->next_free->prev_free = nah->prev_free;
        nah->prev_free->next_free = nah->next_free;
        ah->a.next = nah->a.next;
        nah->a.next->a.prev = ah;

#ifdef DEBUG_MALLOC
        ARENA_TYPE_SET(nah->a.attrs, ARENA_TYPE_DEAD);
#endif
    }

    /* Return the block that contains the called block */
    return ah;
}

void bios_free(void *ptr)
{
    struct free_arena_header *ah;

    ah = (struct free_arena_header *)
        ((struct arena_header *)ptr - 1);

#ifdef DEBUG_MALLOC
    if (ah->a.magic != ARENA_MAGIC)
	dprintf("failed free() magic check: %p\n", ptr);

    if (ARENA_TYPE_GET(ah->a.attrs) != ARENA_TYPE_USED)
	dprintf("invalid arena type: %d\n", ARENA_TYPE_GET(ah->a.attrs));
#endif

    __free_block(ah);
}

__export void free(void *ptr)
{
    dprintf("free(%p) @ %p\n", ptr, __builtin_return_address(0));

    if ( !ptr )
        return;

    sem_down(&__malloc_semaphore, 0);
    firmware->mem->free(ptr);
    sem_up(&__malloc_semaphore);

  /* Here we could insert code to return memory to the system. */
}

/*
 * This is used to insert a block which is not previously on the
 * free list.  Only the a.size field of the arena header is assumed
 * to be valid.
 */
void __inject_free_block(struct free_arena_header *ah)
{
    struct free_arena_header *head =
	&__core_malloc_head[ARENA_HEAP_GET(ah->a.attrs)];
    struct free_arena_header *nah;
    size_t a_end = (size_t) ah + ARENA_SIZE_GET(ah->a.attrs);
    size_t n_end;

    dprintf("inject: %#zx bytes @ %p, heap %u (%p)\n",
	    ARENA_SIZE_GET(ah->a.attrs), ah,
	    ARENA_HEAP_GET(ah->a.attrs), head);

    sem_down(&__malloc_semaphore, 0);

    for (nah = head->a.next ; nah != head ; nah = nah->a.next) {
        n_end = (size_t) nah + ARENA_SIZE_GET(nah->a.attrs);

        /* Is nah entirely beyond this block? */
        if ((size_t) nah >= a_end)
            break;

        /* Is this block entirely beyond nah? */
        if ((size_t) ah >= n_end)
            continue;

	printf("conflict:ah: %p, a_end: %p, nah: %p, n_end: %p\n", ah, a_end, nah, n_end);

        /* Otherwise we have some sort of overlap - reject this block */
	sem_up(&__malloc_semaphore);
        return;
    }

    /* Now, nah should point to the successor block */
    ah->a.next = nah;
    ah->a.prev = nah->a.prev;
    nah->a.prev = ah;
    ah->a.prev->a.next = ah;

    __free_block(ah);

    sem_up(&__malloc_semaphore);
}

/*
 * Free all memory which is tagged with a specific tag.
 */
static void __free_tagged(malloc_tag_t tag) {
    struct free_arena_header *fp, *head;
    int i;

    sem_down(&__malloc_semaphore, 0);

    for (i = 0; i < NHEAP; i++) {
	dprintf("__free_tagged(%u) heap %d\n", tag, i);
	head = &__core_malloc_head[i];
	for (fp = head->a.next ; fp != head ; fp = fp->a.next) {
	    if (ARENA_TYPE_GET(fp->a.attrs) == ARENA_TYPE_USED &&
		fp->a.tag == tag)
		fp = __free_block(fp);
	}
    }

    sem_up(&__malloc_semaphore);
    dprintf("__free_tagged(%u) done\n", tag);
}

void comboot_cleanup_lowmem(com32sys_t *regs)
{
    (void)regs;

    __free_tagged(MALLOC_MODULE);
}
