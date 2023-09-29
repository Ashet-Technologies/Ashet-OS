#ifndef TIMER_H
#define TIMER_H

/*
 * Basic timer function...
 */
typedef uint32_t jiffies_t;
extern volatile jiffies_t __jiffies, __ms_timer;
static inline jiffies_t jiffies(void)
{
    return __jiffies;
}

typedef uint32_t mstime_t;
typedef int32_t  mstimediff_t;
static inline mstime_t ms_timer(void)
{
    return __ms_timer;
}

#endif /* TIMER_H */
