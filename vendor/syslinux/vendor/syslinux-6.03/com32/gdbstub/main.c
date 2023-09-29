#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <console.h>
#include <com32.h>
#include <syslinux/loadfile.h>
#include "serial.h"

#define X86_INT_DB      1
#define X86_INT_BP      3
#define COM32_IDT       ((void*)0x100000)
#define COM32_LOAD_ADDR ((void*)0x101000)
#define STACK_SIZE      0x1000

extern char _start[], _end[];

struct reloc_info {
    void *data;
    size_t len;
    uint32_t old_esp;
    uint32_t reloc_base;
};

static inline void error(const char *msg)
{
    fputs(msg, stderr);
}

static inline uint32_t reloc_ptr(struct reloc_info *ri, void *ptr)
{
    return ri->reloc_base + (uint32_t) ((char *)ptr - _start);
}

static void hijack_interrupt(int intn, uint32_t handler)
{
    struct {
	uint32_t lo;
	uint32_t hi;
    } *idt = COM32_IDT;

    idt[intn].lo = (idt[intn].lo & 0xffff0000) | (handler & 0x0000ffff);
    idt[intn].hi = (idt[intn].hi & 0x0000ffff) | (handler & 0xffff0000);
}

static void shift_cmdline(struct com32_sys_args *com32)
{
    char *p;

    /* Skip leading whitespace */
    for (p = com32->cs_cmdline; *p != '\0' && *p == ' '; p++) ;

    /* Skip first word */
    for (; *p != '\0' && *p != ' '; p++) ;

    /* Skip whitespace after first word */
    for (; *p != '\0' && *p == ' '; p++) ;

    com32->cs_cmdline = p;
}

static __noreturn reloc_entry(struct reloc_info *ri)
{
    extern char int_handler[];
    size_t stack_frame_size = sizeof(struct com32_sys_args) + 4;
    struct com32_sys_args *com32;
    uint32_t module_esp;

    hijack_interrupt(X86_INT_DB, reloc_ptr(ri, int_handler));
    hijack_interrupt(X86_INT_BP, reloc_ptr(ri, int_handler));

    /* Copy module to load address */
    memcpy(COM32_LOAD_ADDR, ri->data, ri->len);

    /* Copy stack frame onto module stack */
    module_esp = (ri->reloc_base - stack_frame_size) & ~15;
    memcpy((void *)module_esp, (void *)ri->old_esp, stack_frame_size);

    /* Fix up command line */
    com32 = (struct com32_sys_args *)(module_esp + 4);
    shift_cmdline(com32);

    /* Set up CPU state to run module and enter GDB */
    asm volatile ("movl %0, %%esp\n\t"
		  "pushf\n\t"
		  "pushl %%cs\n\t"
		  "pushl %1\n\t"
		  "jmp *%2\n\t"::"r" (module_esp),
		  "c"(COM32_LOAD_ADDR), "r"(reloc_ptr(ri, int_handler))
	);
    for (;;) ;			/* shut the compiler up */
}

static inline __noreturn reloc(void *ptr, size_t len)
{
    extern uint32_t __entry_esp;
    size_t total_size = _end - _start;
    __noreturn(*entry_fn) (struct reloc_info *);
    struct reloc_info ri;
    uint32_t esp;
    char *dest;

    /* Calculate relocation address, preserve current stack */
    asm volatile ("movl %%esp, %0\n\t":"=m" (esp));
    dest = (char *)((esp - STACK_SIZE - total_size) & ~3);

    /* Calculate entry point in relocated code */
    entry_fn = (void *)(dest + ((char *)reloc_entry - _start));

    /* Copy all sections to relocation address */
    printf("Relocating %d bytes from %p to %p\n", total_size, _start, dest);
    memcpy(dest, _start, total_size);

    /* Call into relocated code */
    ri.data = ptr;
    ri.len = len;
    ri.old_esp = __entry_esp;
    ri.reloc_base = (uint32_t) dest;
    entry_fn(&ri);
}

int main(int argc, char *argv[])
{
    void *data;
    size_t data_len;

    openconsole(&dev_null_r, &dev_stdcon_w);

    if (argc < 2) {
	error("Usage: gdbstub.c32 com32_file arguments...\n");
	return 1;
    }

    if (loadfile(argv[1], &data, &data_len)) {
	error("Unable to load file\n");
	return 1;
    }

    serial_init();

    /* No more lib calls after this point */
    reloc(data, data_len);
}
