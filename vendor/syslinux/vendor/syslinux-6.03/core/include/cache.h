#ifndef _CACHE_H
#define _CACHE_H

#include <stdint.h>
#include <com32.h>
#include "disk.h"
#include "fs.h"

/* The cache structure */
struct cache {
    block_t block;
    struct cache *prev;
    struct cache *next;
    void *data;
};

/* functions defined in cache.c */
void cache_init(struct device *, int);
const void *get_cache(struct device *, block_t);
struct cache *_get_cache_block(struct device *, block_t);
void cache_lock_block(struct cache *);
size_t cache_read(struct fs_info *, void *, uint64_t, size_t);

#endif /* cache.h */
