/*
 * malloc.c
 *
 * Very simple linked-list based malloc()/free().
 */

#include <syslinux/firmware.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <dprintf.h>
#include <minmax.h>

#include "malloc.h"
#include "thread.h"

DECLARE_INIT_SEMAPHORE(__malloc_semaphore, 1);

static void *__malloc_from_block(struct free_arena_header *fp,
				 size_t size, malloc_tag_t tag)
{
    size_t fsize;
    struct free_arena_header *nfp, *na;
    unsigned int heap = ARENA_HEAP_GET(fp->a.attrs);

    fsize = ARENA_SIZE_GET(fp->a.attrs);

    /* We need the 2* to account for the larger requirements of a free block */
    if ( fsize >= size+2*sizeof(struct arena_header) ) {
        /* Bigger block than required -- split block */
        nfp = (struct free_arena_header *)((char *)fp + size);
        na = fp->a.next;

        ARENA_TYPE_SET(nfp->a.attrs, ARENA_TYPE_FREE);
	ARENA_HEAP_SET(nfp->a.attrs, heap);
        ARENA_SIZE_SET(nfp->a.attrs, fsize-size);
        nfp->a.tag = MALLOC_FREE;
#ifdef DEBUG_MALLOC
	nfp->a.magic = ARENA_MAGIC;
#endif
        ARENA_TYPE_SET(fp->a.attrs, ARENA_TYPE_USED);
        ARENA_SIZE_SET(fp->a.attrs, size);
        fp->a.tag = tag;

        /* Insert into all-block chain */
        nfp->a.prev = fp;
        nfp->a.next = na;
        na->a.prev = nfp;
        fp->a.next = nfp;

        /* Replace current block on free chain */
        nfp->next_free = fp->next_free;
        nfp->prev_free = fp->prev_free;
        fp->next_free->prev_free = nfp;
        fp->prev_free->next_free = nfp;
    } else {
        /* Allocate the whole block */
        ARENA_TYPE_SET(fp->a.attrs, ARENA_TYPE_USED);
        fp->a.tag = tag;

        /* Remove from free chain */
        fp->next_free->prev_free = fp->prev_free;
        fp->prev_free->next_free = fp->next_free;
    }

    return (void *)(&fp->a + 1);
}

void *bios_malloc(size_t size, enum heap heap, malloc_tag_t tag)
{
    struct free_arena_header *fp;
    struct free_arena_header *head = &__core_malloc_head[heap];
    void *p = NULL;

    if (size) {
	/* Add the obligatory arena header, and round up */
	size = (size + 2 * sizeof(struct arena_header) - 1) & ARENA_SIZE_MASK;

	for ( fp = head->next_free ; fp != head ; fp = fp->next_free ) {
	    if ( ARENA_SIZE_GET(fp->a.attrs) >= size ) {
		/* Found fit -- allocate out of this block */
		p = __malloc_from_block(fp, size, tag);
		break;
	    }
        }
    }

    return p;
}

static void *_malloc(size_t size, enum heap heap, malloc_tag_t tag)
{
    void *p;

    dprintf("_malloc(%zu, %u, %u) @ %p = ",
	size, heap, tag, __builtin_return_address(0));

    sem_down(&__malloc_semaphore, 0);
    p = firmware->mem->malloc(size, heap, tag);
    sem_up(&__malloc_semaphore);

    dprintf("%p\n", p);
    return p;
}

__export void *malloc(size_t size)
{
    return _malloc(size, HEAP_MAIN, MALLOC_CORE);
}

__export void *lmalloc(size_t size)
{
    void *p;

    p = _malloc(size, HEAP_LOWMEM, MALLOC_CORE);
    if (!p)
	errno = ENOMEM;
    return p;
}

void *pmapi_lmalloc(size_t size)
{
    return _malloc(size, HEAP_LOWMEM, MALLOC_MODULE);
}

void *bios_realloc(void *ptr, size_t size)
{
    struct free_arena_header *ah, *nah;
    struct free_arena_header *head;

    void *newptr;
    size_t newsize, oldsize, xsize;

    if (!ptr)
	return malloc(size);

    if (size == 0) {
	free(ptr);
	return NULL;
    }

    ah = (struct free_arena_header *)
	((struct arena_header *)ptr - 1);

	head = &__core_malloc_head[ARENA_HEAP_GET(ah->a.attrs)];

#ifdef DEBUG_MALLOC
    if (ah->a.magic != ARENA_MAGIC)
	dprintf("failed realloc() magic check: %p\n", ptr);
#endif

    /* Actual size of the old block */
    //oldsize = ah->a.size;
    oldsize = ARENA_SIZE_GET(ah->a.attrs);

    /* Add the obligatory arena header, and round up */
    newsize = (size + 2 * sizeof(struct arena_header) - 1) & ARENA_SIZE_MASK;

    if (oldsize >= newsize && newsize >= (oldsize >> 2) &&
	oldsize - newsize < 4096) {
	/* This allocation is close enough already. */
	return ptr;
    } else {
	xsize = oldsize;

	nah = ah->a.next;
	if ((char *)nah == (char *)ah + ARENA_SIZE_GET(ah->a.attrs) &&
		ARENA_TYPE_GET(nah->a.attrs) == ARENA_TYPE_FREE &&
		ARENA_SIZE_GET(nah->a.attrs) + oldsize >= newsize) {
	    //nah->a.type == ARENA_TYPE_FREE &&
	    //oldsize + nah->a.size >= newsize) {
	    /* Merge in subsequent free block */
	    ah->a.next = nah->a.next;
	    ah->a.next->a.prev = ah;
	    nah->next_free->prev_free = nah->prev_free;
	    nah->prev_free->next_free = nah->next_free;
	    ARENA_SIZE_SET(ah->a.attrs, ARENA_SIZE_GET(ah->a.attrs) +
			   ARENA_SIZE_GET(nah->a.attrs));
	    xsize = ARENA_SIZE_GET(ah->a.attrs);
	}

	if (xsize >= newsize) {
	    /* We can reallocate in place */
	    if (xsize >= newsize + 2 * sizeof(struct arena_header)) {
		/* Residual free block at end */
		nah = (struct free_arena_header *)((char *)ah + newsize);
		ARENA_TYPE_SET(nah->a.attrs, ARENA_TYPE_FREE);
		ARENA_SIZE_SET(nah->a.attrs, xsize - newsize);
		ARENA_SIZE_SET(ah->a.attrs, newsize);
		ARENA_HEAP_SET(nah->a.attrs, ARENA_HEAP_GET(ah->a.attrs));

#ifdef DEBUG_MALLOC
		nah->a.magic = ARENA_MAGIC;
#endif

		//nah->a.type = ARENA_TYPE_FREE;
		//nah->a.size = xsize - newsize;
		//ah->a.size = newsize;

		/* Insert into block list */
		nah->a.next = ah->a.next;
		ah->a.next = nah;
		nah->a.next->a.prev = nah;
		nah->a.prev = ah;

		/* Insert into free list */
		if (newsize > oldsize) {
		    /* Hack: this free block is in the path of a memory object
		       which has already been grown at least once.  As such, put
		       it at the *end* of the freelist instead of the beginning;
		       trying to save it for future realloc()s of the same block. */
		    nah->prev_free = head->prev_free;
		    nah->next_free = head;
		    head->prev_free = nah;
		    nah->prev_free->next_free = nah;
		} else {
		    nah->next_free = head->next_free;
		    nah->prev_free = head;
		    head->next_free = nah;
		    nah->next_free->prev_free = nah;
		}
   	    }
	    /* otherwise, use up the whole block */
	    return ptr;
	} else {
	    /* Last resort: need to allocate a new block and copy */
	    oldsize -= sizeof(struct arena_header);
	    newptr = malloc(size);
	    if (newptr) {
		memcpy(newptr, ptr, min(size, oldsize));
		free(ptr);
	    }
	    return newptr;
	}
    }
}

__export void *realloc(void *ptr, size_t size)
{
    return firmware->mem->realloc(ptr, size);
}

__export void *zalloc(size_t size)
{
    void *ptr;

    ptr = malloc(size);
    if (ptr)
	memset(ptr, 0, size);

    return ptr;
}
