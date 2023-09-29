#include "thread.h"

struct thread __root_thread = {
    .thread_magic = THREAD_MAGIC,
    .name = "root",
    .list = { .next = &__root_thread.list, .prev = &__root_thread.list },
    .blocked = NULL,
    .prio = 0,
};

struct thread *__current = &__root_thread;
