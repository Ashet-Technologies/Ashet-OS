#ifndef KABOOM_H
#define KABOOM_H

/*
 * Death!  The macro trick is to avoid symbol conflict with
 * the real-mode symbol kaboom.
 */
__noreturn _kaboom(void);
#define kaboom() _kaboom()

#endif /* KABOOM_H */
