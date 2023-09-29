/*
 * Copyright (C) 2011 Paulo Alcantara <pcacjr@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the
 * Free Software Foundation, Inc.,
 * 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/

#ifndef _RUNLIST_H_
#define _RUNLIST_H_

struct runlist_element {
    uint64_t vcn;
    int64_t lcn;
    uint64_t len;
};

struct runlist {
    struct runlist_element run;
    struct runlist *next;
};

static struct runlist *tail;

static inline bool runlist_is_empty(struct runlist *rlist)
{
    return !rlist;
}

static inline struct runlist *runlist_alloc(void)
{
    struct runlist *rlist;

    rlist = malloc(sizeof *rlist);
    if (!rlist)
        malloc_error("runlist structure");

    rlist->next = NULL;

    return rlist;
}

static inline void runlist_append(struct runlist **rlist,
                                struct runlist_element *elem)
{
    struct runlist *n = runlist_alloc();

    n->run = *elem;

    if (runlist_is_empty(*rlist)) {
        *rlist = n;
        tail = n;
    } else {
        tail->next = n;
        tail = n;
    }
}

static inline struct runlist *runlist_remove(struct runlist **rlist)
{
    struct runlist *ret;

    if (runlist_is_empty(*rlist))
        return NULL;

    ret = *rlist;
    *rlist = ret->next;

    return ret;
}

#endif /* _RUNLIST_H_ */
