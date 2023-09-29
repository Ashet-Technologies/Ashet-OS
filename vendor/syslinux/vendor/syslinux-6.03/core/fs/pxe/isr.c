/*
 * core/fs/pxe/isr.c
 *
 * Stub invoked on return from real mode including from an interrupt.
 * Interrupts are locked out on entry.
 */

#include "core.h"
#include "thread.h"
#include "pxe.h"
#include <string.h>
#include <sys/cpu.h>
#include <sys/io.h>

extern uint8_t pxe_irq_pending;
extern volatile uint8_t pxe_need_poll;
static DECLARE_INIT_SEMAPHORE(pxe_receive_thread_sem, 0);
static DECLARE_INIT_SEMAPHORE(pxe_poll_thread_sem, 0);
static struct thread *pxe_thread, *poll_thread;

#ifndef PXE_POLL_FORCE
#  define PXE_POLL_FORCE 0
#endif

#ifndef PXE_POLL_BY_MODEL
#  define PXE_POLL_BY_MODEL 1
#endif

/*
 * Note: this *must* be called with interrupts enabled.
 */
static bool install_irq_vector(uint8_t irq, void (*isr)(void), far_ptr_t *old)
{
    far_ptr_t *entry;
    unsigned int vec;
    uint8_t mask, mymask;
    uint32_t now;
    bool ok;

    if (irq < 8)
	vec = irq + 0x08;
    else if (irq < 16)
	vec = (irq - 8) + 0x70;
    else
	return false;

    cli();

    if (pxe_need_poll) {
	sti();
	return false;
    }

    entry = (far_ptr_t *)(vec << 2);
    *old = *entry;
    entry->ptr = (uint32_t)isr;

    /* Enable this interrupt at the PIC level, just in case... */
    mymask = ~(1 << (irq & 7));
    if (irq >= 8) {
	mask = inb(0x21);
	mask &= ~(1 << 2);	/* Enable cascade */
	outb(mask, 0x21);
 	mask = inb(0xa1);
	mask &= mymask;
	outb(mask, 0xa1);
    } else {
 	mask = inb(0x21);
	mask &= mymask;
	outb(mask, 0x21);
    }

    sti();

    now = jiffies();

    /* Some time to watch for stuck interrupts */
    while (jiffies() - now < 4 && (ok = !pxe_need_poll))
	hlt();

    if (!ok)
	*entry = *old;		/* Restore the old vector */

    ddprintf("UNDI: IRQ %d(0x%02x): %04x:%04x -> %04x:%04x\n", irq, vec,
	   old->seg, old->offs, entry->seg, entry->offs);

    return ok;
}

static bool uninstall_irq_vector(uint8_t irq, void (*isr), far_ptr_t *old)
{
    far_ptr_t *entry;
    unsigned int vec;
    bool rv;

    if (!irq)
	return true;		/* Nothing to uninstall */

    if (irq < 8)
	vec = irq + 0x08;
    else if (irq < 16)
	vec = (irq - 8) + 0x70;
    else
	return false;

    cli();

    entry = (far_ptr_t *)(vec << 2);

    if (entry->ptr != (uint32_t)isr) {
	rv = false;
    } else {
	*entry = *old;
	rv = true;
    }

    sti();
    return rv;
}

static void pxe_poll_wakeups(void)
{
    static jiffies_t last_jiffies = 0;
    jiffies_t now = jiffies();

    if (pxe_need_poll == 1) {
	/* If we need polling now, activate polling */
	pxe_need_poll = 3;
	sem_up(&pxe_poll_thread_sem);
    }

    if (now != last_jiffies) {
	last_jiffies = now;
	__thread_process_timeouts();
    }

    if (pxe_irq_pending) {
	pxe_irq_pending = 0;
	sem_up(&pxe_receive_thread_sem);
    }
}

static void pxe_process_irq(void)
{
    static __lowmem t_PXENV_UNDI_ISR isr;

    uint16_t func = PXENV_UNDI_ISR_IN_PROCESS; /* First time */
    bool done = false;

    while (!done) {
        memset(&isr, 0, sizeof isr);
        isr.FuncFlag = func;
        func = PXENV_UNDI_ISR_IN_GET_NEXT; /* Next time */

        pxe_call(PXENV_UNDI_ISR, &isr);

        switch (isr.FuncFlag) {
        case PXENV_UNDI_ISR_OUT_DONE:
	    done = true;
	    break;

        case PXENV_UNDI_ISR_OUT_TRANSMIT:
	    /* Transmit complete - nothing for us to do */
	    break;

        case PXENV_UNDI_ISR_OUT_RECEIVE:
	    undiif_input(&isr);
	    break;

        case PXENV_UNDI_ISR_OUT_BUSY:
	/* ISR busy, this should not happen */
	    done = true;
	    break;

        default:
	/* Invalid return code, this should not happen */
	    done = true;
	    break;
        }
    }
}

static void pxe_receive_thread(void *dummy)
{
    (void)dummy;

    for (;;) {
	sem_down(&pxe_receive_thread_sem, 0);
	pxe_process_irq();
    }
}

static bool pxe_isr_poll(void)
{
    static __lowmem t_PXENV_UNDI_ISR isr;

    isr.FuncFlag = PXENV_UNDI_ISR_IN_START;
    pxe_call(PXENV_UNDI_ISR, &isr);

    return isr.FuncFlag == PXENV_UNDI_ISR_OUT_OURS;
}

static void pxe_poll_thread(void *dummy)
{
    (void)dummy;

    /* Block indefinitely unless activated */
    sem_down(&pxe_poll_thread_sem, 0);

    for (;;) {
	cli();
	if (pxe_receive_thread_sem.count < 0 && pxe_isr_poll())
	    sem_up(&pxe_receive_thread_sem);
	else
	    __schedule();
	sti();
	cpu_relax();
    }
}

/*
 * This does preparations and enables the PXE thread
 */
void pxe_init_isr(void)
{
    start_idle_thread();
    sched_hook_func = pxe_poll_wakeups;
    /*
     * Run the pxe receive thread at elevated priority, since the UNDI
     * stack is likely to have very limited memory available; therefore to
     * avoid packet loss we need to move it into memory that we ourselves
     * manage, as soon as possible.
     */
    core_pm_hook = __schedule;

    pxe_thread = start_thread("pxe receive", 16384, -20,
			      pxe_receive_thread, NULL);
}

/*
 * Actually start the interrupt routine inside the UNDI stack
 */
void pxe_start_isr(void)
{
    int irq = pxe_undi_info.IntNumber;

    if (irq == 2)
	irq = 9;		/* IRQ 2 is really IRQ 9 */
    else if (irq > 15)
	irq = 0;		/* Invalid IRQ */

    pxe_irq_vector = irq;

    if (irq) {
	if (!install_irq_vector(irq, pxe_isr, &pxe_irq_chain))
	    irq = 0;		/* Install failed or stuck interrupt */
    }
    
    poll_thread = start_thread("pxe poll", 4096, POLL_THREAD_PRIORITY,
			       pxe_poll_thread, NULL);

    if (!irq ||	!(pxe_undi_iface.ServiceFlags & PXE_UNDI_IFACE_FLAG_IRQ)) {
	asm volatile("orb $1,%0" : "+m" (pxe_need_poll));
	dprintf("pxe_start_isr: forcing pxe_need_poll\n");
    } else if (PXE_POLL_BY_MODEL) {
	dprintf("pxe_start_isr: trying poll by model\n");
	int hwad = ((int)MAC[0] << 16) + ((int)MAC[1] << 8) + MAC[2];
	dprintf("pxe_start_isr: got %06x %04x\n", hwad, pxe_undi_iface.ServiceFlags);
	if ((hwad == 0x000023ae) && (pxe_undi_iface.ServiceFlags == 0xdc1b) ||
	    (hwad == 0x005c260a) && (pxe_undi_iface.ServiceFlags == 0xdc1b) ||
	    (hwad == 0x00180373) && (pxe_undi_iface.ServiceFlags == 0xdc1b)) {
		asm volatile("orb $1,%0" : "+m" (pxe_need_poll));
		dprintf("pxe_start_isr: forcing pxe_need_poll by model\n");
	}
    }
}

int reset_pxe(void)
{
    static __lowmem struct s_PXENV_UNDI_CLOSE undi_close;

    sched_hook_func = NULL;
    core_pm_hook = core_pm_null_hook;
    kill_thread(pxe_thread);

    memset(&undi_close, 0, sizeof(undi_close));
    pxe_call(PXENV_UNDI_CLOSE, &undi_close);

    if (undi_close.Status)
	printf("PXENV_UNDI_CLOSE failed: 0x%x\n", undi_close.Status);

    if (pxe_irq_vector)
	uninstall_irq_vector(pxe_irq_vector, pxe_isr, &pxe_irq_chain);
    if (poll_thread)
	kill_thread(poll_thread);

    return undi_close.Status;
}
