#include <com32.h>

/* When we don't need to pass any registers, it's convenient to just
   be able to pass a prepared all-zero structure. */
const com32sys_t __com32_zero_regs;
