#ifndef __LWIP_ARCH_CC_H__
#define __LWIP_ARCH_CC_H__

#include <klibc/compiler.h>
#include <inttypes.h>
#include <errno.h>
#include <stdlib.h>
#include <kaboom.h>
#include <stdio.h>

#define BYTE_ORDER LITTLE_ENDIAN

typedef uint8_t  u8_t;
typedef int8_t   s8_t;
typedef uint16_t u16_t;
typedef int16_t  s16_t;
typedef uint32_t u32_t;
typedef int32_t  s32_t;

typedef uintptr_t mem_ptr_t;

#define PACK_STRUCT_STRUCT	__packed

#define LWIP_PLATFORM_USE_DPRINTF

#ifdef LWIP_PLATFORM_USE_DPRINTF
#  include <dprintf.h>
#  define LWIP_PLATFORM_PRINTF dprintf
#else
#  define LWIP_PLATFORM_PRINTF printf
#endif


#if 1
#define LWIP_PLATFORM_DIAG(x)	do { LWIP_PLATFORM_PRINTF x; } while(0)
#define LWIP_PLATFORM_ASSERT(x)	do { LWIP_PLATFORM_PRINTF("LWIP(%s,%d,%p): %s", __FILE__, __LINE__, __builtin_return_address(0), (x)); kaboom(); } while(0)
#else
#define LWIP_PLATFORM_DIAG(x)	((void)0) /* For now... */
#define LWIP_PLATFORM_ASSERT(x)	kaboom()
#endif

#define U16_F	PRIu16
#define S16_F	PRId16
#define X16_F	PRIx16
#define U32_F	PRIu16
#define S32_F	PRId16
#define X32_F	PRIx16
#define SZT_F	"zu"

#endif /* __LWIP_ARCH_CC_H__ */
