#ifndef CORE_H
#define CORE_H

#include <klibc/compiler.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdbool.h>
#include <inttypes.h>
#include <stdio.h>
#include <dprintf.h>
#include <com32.h>
#include <errno.h>
#include <syslinux/pmapi.h>
#include <syslinux/sysappend.h>
#include <kaboom.h>
#include <timer.h>

extern char core_xfer_buf[65536];
extern char core_cache_buf[65536];
extern char trackbuf[];
extern char CurrentDirName[];
extern char SubvolName[];
extern char ConfigName[];
extern char config_cwd[];
extern char cmd_line[];
extern char ConfigFile[];
extern char syslinux_banner[];
extern char copyright_str[];

extern const size_t __syslinux_shuffler_size;

static inline size_t syslinux_shuffler_size(void)
{
    return __syslinux_shuffler_size;
}

/*
 * Mark symbols that are only used by BIOS as __weak until we can move
 * all references out of the generic (EFI + BIOS) code and into
 * BIOS-specific code.
 */
extern __weak uint16_t BIOSName;
extern __weak char KernelName[];
extern __weak char StackBuf[];

extern uint8_t KbdMap[256];

extern const uint16_t IPAppends[];
extern size_t numIPAppends;

extern uint16_t SerialPort;
extern uint16_t BaudDivisor;
extern uint8_t FlowOutput;
extern uint8_t FlowInput;
extern uint8_t FlowIgnore;

extern uint8_t ScrollAttribute;
extern uint16_t DisplayCon;

/* diskstart.inc isolinux.asm*/
extern void getlinsec(void);

/* pm.inc */
void core_pm_null_hook(void);
extern void (*core_pm_hook)(void);

/* getc.inc */
extern void core_open(void);

/* adv.inc */
extern void adv_init(void);
extern void adv_write(void);

/* hello.c */
extern void myputs(const char*);

/* idle.c */
extern int (*idle_hook_func)(void);
extern void __idle(void);
extern void reset_idle(void);

/* mem/malloc.c, mem/free.c, mem/init.c */
extern void *lmalloc(size_t);
extern void *pmapi_lmalloc(size_t);
extern void *zalloc(size_t);
extern void free(void *);
extern void mem_init(void);

/* sysappend.c */
extern void print_sysappend(void);
extern const char *sysappend_strings[SYSAPPEND_MAX];
extern uint32_t SysAppends;
extern void sysappend_set_uuid(const uint8_t *uuid);
extern void sysappend_set_fs_uuid(void);

void __cdecl core_intcall(uint8_t, const com32sys_t *, com32sys_t *);
void __cdecl core_farcall(uint32_t, const com32sys_t *, com32sys_t *);
int __cdecl core_cfarcall(uint32_t, const void *, uint32_t);

extern const com32sys_t zero_regs;
void call16(void (*)(void), const com32sys_t *, com32sys_t *);

/*
 * __lowmem is in the low 1 MB; __bss16 in the low 64K
 */
#ifdef __SYSLINUX_CORE__	/* Not supported in modules */
# define __lowmem __attribute__((nocommon,section(".lowmem")))
# define __bss16  __attribute__((nocommon,section(".bss16")))
#endif

/*
 * Helper routine to return a specific set of flags
 */
static inline void set_flags(com32sys_t *regs, uint32_t flags)
{
    uint32_t eflags;

    eflags = regs->eflags.l;
    eflags &= ~(EFLAGS_CF|EFLAGS_PF|EFLAGS_AF|EFLAGS_ZF|EFLAGS_SF|EFLAGS_OF);
    eflags |= flags;
    regs->eflags.l = eflags;
}

extern int start_ldlinux(int argc, char **argv);
extern int create_args_and_load(char *);

extern void write_serial(char data);
extern void writestr(char *str);
extern void writechr(char data);
extern void crlf(void);
extern int pollchar(void);
extern char getchar(char *hi);
extern uint8_t kbd_shiftflags(void);
static inline bool shift_is_held(void)
{
    return !!(kbd_shiftflags() & 0x5d); /* Caps/Scroll/Alt/Shift */
}
static inline bool ctrl_is_held(void)
{
    return !!(kbd_shiftflags() & 0x04); /* Only Ctrl */
}

extern void cleanup_hardware(void);
extern void sirq_cleanup(void);
extern void adjust_screen(void);

extern void execute(const char *cmdline, uint32_t type, bool sysappend);
extern void load_kernel(const char *cmdline);

extern void dmi_init(void);

extern void do_sysappend(char *buf);

extern void load_env32(com32sys_t *regs);

#endif /* CORE_H */
