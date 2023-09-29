#include "core.h"
#include <dprintf.h>

void pm_debug_msg(com32sys_t *regs)
{
    (void)regs;			/* For the non-DEBUG configuration */

    dprintf("%s\n", MK_PTR(0, regs->eax.w[0]));
}
