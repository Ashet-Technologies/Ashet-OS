#ifndef _FOUNDATION_LIBC_SETJMP_H_
#define _FOUNDATION_LIBC_SETJMP_H_

typedef unsigned int jmp_buf[1];

int                  setjmp(jmp_buf) __attribute__((__returns_twice__));
_Noreturn void       longjmp(jmp_buf env, int val);

#define setjmp setjmp // must be a macro

#endif
