#ifndef ASHET_OS_cc_h
#define ASHET_OS_cc_h

#include <stdbool.h>
#include <stdint.h>

// ashet apis:
extern void ashet_lockInterrupts(bool *state);
extern void ashet_unlockInterrupts(bool state);
extern uint32_t ashet_rand(void);

#define LWIP_PLATFORM_DIAG(x)   // TODO: Implement these
#define LWIP_PLATFORM_ASSERT(x) // TODO: Implement these

#define BYTE_ORDER LITTLE_ENDIAN

#define LWIP_RAND() ((u32_t)ashet_rand())

#define LWIP_NO_STDDEF_H 0
#define LWIP_NO_STDINT_H 0
#define LWIP_NO_INTTYPES_H 1
#define LWIP_NO_LIMITS_H 0
#define LWIP_NO_CTYPE_H 1

#define LWIP_UNUSED_ARG(x) (void)x
#define LWIP_PROVIDE_ERRNO 1

// Critical section support:
// https://www.nongnu.org/lwip/2_1_x/group__sys__prot.html

#define SYS_ARCH_DECL_PROTECT(lev) bool lev
#define SYS_ARCH_PROTECT(lev) ashet_lockInterrupts(&lev)
#define SYS_ARCH_UNPROTECT(lev) ashet_unlockInterrupts(lev)

#endif // ASHET_OS_cc_h
