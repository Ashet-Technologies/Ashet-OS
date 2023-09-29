/*
 * free.c
 *
 * Very simple linked-list based malloc()/free().
 */

#include <stdlib.h>
#include "malloc.h"

static struct free_arena_header *__free_block(struct free_arena_header *ah)
{
    struct free_arena_header *pah, *nah;

    pah = ah->a.prev;
    nah = ah->a.next;
    if (pah->a.type == ARENA_TYPE_FREE &&
	(char *)pah + pah->a.size == (char *)ah) {
	/* Coalesce into the previous block */
	pah->a.size += ah->a.size;
	pah->a.next = nah;
	nah->a.prev = pah;

#ifdef DEBUG_MALLOC
	ah->a.type = ARENA_TYPE_DEAD;
#endif

	ah = pah;
	pah = ah->a.prev;
    } else {
	/* Need to add this block to the free chain */
	ah->a.type = ARENA_TYPE_FREE;

	ah->next_free = __malloc_head.next_free;
	ah->prev_free = &__malloc_head;
	__malloc_head.next_free = ah;
	ah->next_free->prev_free = ah;
    }

    /* In either of the previous cases, we might be able to merge
       with the subsequent block... */
    if (nah->a.type == ARENA_TYPE_FREE &&
	(char *)ah + ah->a.size == (char *)nah) {
	ah->a.size += nah->a.size;

	/* Remove the old block from the chains */
	nah->next_free->prev_free = nah->prev_free;
	nah->prev_free->next_free = nah->next_free;
	ah->a.next = nah->a.next;
	nah->a.next->a.prev = ah;

#ifdef DEBUG_MALLOC
	nah->a.type = ARENA_TYPE_DEAD;
#endif
    }

    /* Return the block that contains the called block */
    return ah;
}

void free(void *ptr)
{
    struct free_arena_header *ah;

    if (!ptr)
	return;

    ah = (struct free_arena_header *)
	((struct arena_header *)ptr - 1);

    __free_block(ah);

    /* Here we could insert code to return memory to the system. */
}
