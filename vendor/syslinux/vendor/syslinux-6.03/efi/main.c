/*
 * Copyright 2011-2014 Intel Corporation - All Rights Reserved
 */

#include <codepage.h>
#include <core.h>
#include <fs.h>
#include <com32.h>
#include <syslinux/memscan.h>
#include <syslinux/firmware.h>
#include <syslinux/linux.h>
#include <sys/ansi.h>
#include <setjmp.h>

#include "efi.h"
#include "fio.h"
#include "version.h"

__export uint16_t PXERetry;
__export char copyright_str[] = "Copyright (C) 2011-" YEAR_STR "\n";
uint8_t SerialNotice = 1;
__export char syslinux_banner[] = "Syslinux " VERSION_STR " (EFI; " DATE_STR ")\n";
char CurrentDirName[CURRENTDIR_MAX];
struct com32_sys_args __com32;

uint32_t _IdleTimer = 0;
char __lowmem_heap[32];
uint32_t BIOS_timer_next;
uint32_t timer_irq;
__export uint8_t KbdMap[256];
char aux_seg[256];

static jmp_buf load_error_buf;

static inline EFI_STATUS
efi_close_protocol(EFI_HANDLE handle, EFI_GUID *guid, EFI_HANDLE agent,
		   EFI_HANDLE controller)
{
    return uefi_call_wrapper(BS->CloseProtocol, 4, handle,
			     guid, agent, controller);
}

struct efi_binding *efi_create_binding(EFI_GUID *bguid, EFI_GUID *pguid)
{
    EFI_SERVICE_BINDING *sbp;
    struct efi_binding *b;
    EFI_STATUS status;
    EFI_HANDLE protocol, child, *handles = NULL;
    UINTN i, nr_handles = 0;

    b = malloc(sizeof(*b));
    if (!b)
	return NULL;

    status = LibLocateHandle(ByProtocol, bguid, NULL, &nr_handles, &handles);
    if (status != EFI_SUCCESS)
	goto free_binding;

    for (i = 0; i < nr_handles; i++) {
	status = uefi_call_wrapper(BS->OpenProtocol, 6, handles[i],
				   bguid, (void **)&sbp,
				   image_handle, handles[i],
				   EFI_OPEN_PROTOCOL_GET_PROTOCOL);
	if (status == EFI_SUCCESS)
	    break;

	uefi_call_wrapper(BS->CloseProtocol, 4, handles[i], bguid,
			  image_handle, handles[i]);
    }

    if (i == nr_handles)
	goto free_binding;

    child = NULL;

    status = uefi_call_wrapper(sbp->CreateChild, 2, sbp, (EFI_HANDLE *)&child);
    if (status != EFI_SUCCESS)
	goto close_protocol;

    status = uefi_call_wrapper(BS->OpenProtocol, 6, child,
			      pguid, (void **)&protocol,
			      image_handle, sbp,
			      EFI_OPEN_PROTOCOL_GET_PROTOCOL);
    if (status != EFI_SUCCESS)
	goto destroy_child;

    b->parent = handles[i];
    b->binding = sbp;
    b->child = child;
    b->this = protocol;

    return b;

destroy_child:
    uefi_call_wrapper(sbp->DestroyChild, 2, sbp, child);

close_protocol:
    uefi_call_wrapper(BS->CloseProtocol, 4, handles[i], bguid,
		      image_handle, handles[i]);

free_binding:
    free(b);
    return NULL;
}

void efi_destroy_binding(struct efi_binding *b, EFI_GUID *guid)
{
    efi_close_protocol(b->child, guid, image_handle, b->binding);
    uefi_call_wrapper(b->binding->DestroyChild, 2, b->binding, b->child);
    efi_close_protocol(b->parent, guid, image_handle, b->parent);

    free(b);
}

#undef kaboom
void kaboom(void)
{
}

void printf_init(void)
{
}

__export void local_boot(uint16_t ax)
{
    /*
     * Inform the firmware that we failed to execute correctly, which
     * will trigger the next entry in the EFI Boot Manager list.
     */
    longjmp(load_error_buf, 1);
}

void bios_timer_cleanup(void)
{
}

char trackbuf[4096];

void __cdecl core_farcall(uint32_t c, const com32sys_t *a, com32sys_t *b)
{
}

__export struct firmware *firmware = NULL;
__export void *__syslinux_adv_ptr;
__export size_t __syslinux_adv_size;
char core_xfer_buf[65536];
struct iso_boot_info {
	uint32_t pvd;               /* LBA of primary volume descriptor */
	uint32_t file;              /* LBA of boot file */
	uint32_t length;            /* Length of boot file */
	uint32_t csum;              /* Checksum of boot file */
	uint32_t reserved[10];      /* Currently unused */
} iso_boot_info;

uint8_t DHCPMagic;
uint32_t RebootTime;

void pxenv(void)
{
}

uint16_t BIOS_fbm = 1;
far_ptr_t InitStack;
far_ptr_t PXEEntry;

void gpxe_unload(void)
{
}

void do_idle(void)
{
}

void pxe_int1a(void)
{
}

uint8_t KeepPXE;

struct semaphore;
mstime_t sem_down(struct semaphore *sem, mstime_t time)
{
	/* EFI is single threaded */
	return 0;
}

void sem_up(struct semaphore *sem)
{
	/* EFI is single threaded */
}

__export volatile uint32_t __ms_timer = 0;
volatile uint32_t __jiffies = 0;

void efi_write_char(uint8_t ch, uint8_t attribute)
{
	SIMPLE_TEXT_OUTPUT_INTERFACE *out = ST->ConOut;
	uint16_t c[2];

	uefi_call_wrapper(out->SetAttribute, 2, out, attribute);

	/* Lookup primary Unicode encoding in the system codepage */
	c[0] = codepage.uni[0][ch];
	c[1] = '\0';

	uefi_call_wrapper(out->OutputString, 2, out, c);
}

static void efi_showcursor(const struct term_state *st)
{
	SIMPLE_TEXT_OUTPUT_INTERFACE *out = ST->ConOut;
	bool cursor = st->cursor ? true : false;

	uefi_call_wrapper(out->EnableCursor, 2, out, cursor);
}

static void efi_set_cursor(int x, int y, bool visible)
{
	SIMPLE_TEXT_OUTPUT_INTERFACE *out = ST->ConOut;

	uefi_call_wrapper(out->SetCursorPosition, 3, out, x, y);
}

static void efi_scroll_up(uint8_t cols, uint8_t rows, uint8_t attribute)
{
	efi_write_char('\n', 0);
	efi_write_char('\r', 0);
}

static void efi_get_mode(int *cols, int *rows)
{
	SIMPLE_TEXT_OUTPUT_INTERFACE *out = ST->ConOut;
	UINTN c, r;

	uefi_call_wrapper(out->QueryMode, 4, out, out->Mode->Mode, &c, &r);
	*rows = r;
	*cols = c;
}

static void efi_erase(int x0, int y0, int x1, int y1, uint8_t attribute)
{
	SIMPLE_TEXT_OUTPUT_INTERFACE *out = ST->ConOut;
	int cols, rows;

	efi_get_mode(&cols, &rows);

	/*
	 * The BIOS version of this function has the ability to erase
	 * parts or all of the screen - the UEFI console doesn't
	 * support this so we just set the cursor position unless
	 * we're clearing the whole screen.
	 */
	if (!x0 && y0 == (cols - 1)) {
		/* Really clear the screen */
		uefi_call_wrapper(out->ClearScreen, 1, out);
	} else {
		uefi_call_wrapper(out->SetCursorPosition, 3, out, y1, x1);
	}
}

static void efi_text_mode(void)
{
}

static void efi_get_cursor(uint8_t *x, uint8_t *y)
{
	SIMPLE_TEXT_OUTPUT_INTERFACE *out = ST->ConOut;
	*x = out->Mode->CursorColumn;
	*y = out->Mode->CursorRow;
}

struct output_ops efi_ops = {
	.erase = efi_erase,
	.write_char = efi_write_char,
	.showcursor = efi_showcursor,
	.set_cursor = efi_set_cursor,
	.scroll_up = efi_scroll_up,
	.get_mode = efi_get_mode,
	.text_mode = efi_text_mode,
	.get_cursor = efi_get_cursor,
};

char SubvolName[2];
static inline EFI_MEMORY_DESCRIPTOR *
get_memory_map(UINTN *nr_entries, UINTN *key, UINTN *desc_sz,
	       uint32_t *desc_ver)
{
	return LibMemoryMap(nr_entries, key, desc_sz, desc_ver);
}


int efi_scan_memory(scan_memory_callback_t callback, void *data)
{
	UINTN i, nr_entries, key, desc_sz;
	UINTN buf, bufpos;
	UINT32 desc_ver;
	int rv = 0;

	buf = (UINTN)get_memory_map(&nr_entries, &key, &desc_sz, &desc_ver);
	if (!buf)
		return -1;
	bufpos = buf;

	for (i = 0; i < nr_entries; bufpos += desc_sz, i++) {
		EFI_MEMORY_DESCRIPTOR *m;
		UINT64 region_sz;
		enum syslinux_memmap_types type;

		m = (EFI_MEMORY_DESCRIPTOR *)bufpos;
		region_sz = m->NumberOfPages * EFI_PAGE_SIZE;

		switch (m->Type) {
                case EfiConventionalMemory:
			type = SMT_FREE;
                        break;
		default:
			type = SMT_RESERVED;
			break;
		}

		rv = callback(data, m->PhysicalStart, region_sz, type);
		if (rv)
			break;
	}

	FreePool((void *)buf);
	return rv;
}

static struct syslinux_memscan efi_memscan = {
    .func = efi_scan_memory,
};

extern uint16_t *bios_free_mem;
void efi_init(void)
{
	/* XXX timer */
	*bios_free_mem = 0;
	syslinux_memscan_add(&efi_memscan);
	mem_init();
}

char efi_getchar(char *hi)
{
	SIMPLE_INPUT_INTERFACE *in = ST->ConIn;
	EFI_INPUT_KEY key;
	EFI_STATUS status;

	do {
		status = uefi_call_wrapper(in->ReadKeyStroke, 2, in, &key);
	} while (status == EFI_NOT_READY);

	if (!key.ScanCode)
		return (char)key.UnicodeChar;

	/*
	 * We currently only handle scan codes that fit in 8 bits.
	 */
	*hi = (char)key.ScanCode;
	return 0;
}

int efi_pollchar(void)
{
	SIMPLE_INPUT_INTERFACE *in = ST->ConIn;
	EFI_STATUS status;

	status = WaitForSingleEvent(in->WaitForKey, 1);
	return status != EFI_TIMEOUT;
}

struct input_ops efi_iops = {
	.getchar = efi_getchar,
	.pollchar = efi_pollchar,
};

extern void efi_adv_init(void);
extern int efi_adv_write(void);

struct adv_ops efi_adv_ops = {
	.init = efi_adv_init,
	.write = efi_adv_write,
};

struct efi_info {
	uint32_t load_signature;
	uint32_t systab;
	uint32_t desc_size;
	uint32_t desc_version;
	uint32_t memmap;
	uint32_t memmap_size;
	uint32_t systab_hi;
	uint32_t memmap_hi;
};

#define E820MAX	128
#define E820_RAM	1
#define E820_RESERVED	2
#define E820_ACPI	3
#define E820_NVS	4
#define E820_UNUSABLE	5

#define BOOT_SIGNATURE	0xaa55
#define SYSLINUX_EFILDR	0x30	/* Is this published value? */
#define DEFAULT_TIMER_TICK_DURATION 	500000 /* 500000 == 500000 * 100 * 10^-9 == 50 msec */
#define DEFAULT_MSTIMER_INC		0x32	/* 50 msec */
struct e820_entry {
	uint64_t start;
	uint64_t len;
	uint32_t type;
} __packed;

struct boot_params {
	struct screen_info screen_info;
	uint8_t _pad[0x1c0 - sizeof(struct screen_info)];
	struct efi_info efi;
	uint8_t _pad2[8];
	uint8_t e820_entries;
	uint8_t _pad3[0x2d0 - 0x1e8 - sizeof(uint8_t)];
	struct e820_entry e820_map[E820MAX];
} __packed;

/* Allocate boot parameter block aligned to page */
#define BOOT_PARAM_BLKSIZE	EFI_SIZE_TO_PAGES(sizeof(struct boot_params)) * EFI_PAGE_SIZE

/* Routines in support of efi boot loader were obtained from
 * http://git.kernel.org/?p=boot/efilinux/efilinux.git:
 * kernel_jump(), handover_jump(),
 * emalloc()/efree, alloc_pages/free_pages
 * allocate_pool()/free_pool()
 * memory_map()
 */ 
extern void kernel_jump(EFI_PHYSICAL_ADDRESS kernel_start,
			       struct boot_params *boot_params);
#if __SIZEOF_POINTER__ == 4
#define EFI_LOAD_SIG	"EL32"
#elif __SIZEOF_POINTER__ == 8
#define EFI_LOAD_SIG	"EL64"
#else
#error "unsupported architecture"
#endif

struct dt_desc {
	uint16_t limit;
	uint64_t *base;
} __packed;

struct dt_desc gdt = { 0x800, (uint64_t *)0 };
struct dt_desc idt = { 0, 0 };

static inline EFI_MEMORY_DESCRIPTOR *
get_mem_desc(unsigned long memmap, UINTN desc_sz, int i)
{
	return (EFI_MEMORY_DESCRIPTOR *)(memmap + (i * desc_sz));
}

EFI_HANDLE image_handle;

static inline UINT64 round_up(UINT64 x, UINT64 y)
{
	return (((x - 1) | (y - 1)) + 1);
}

static inline UINT64 round_down(UINT64 x, UINT64 y)
{
	return (x & ~(y - 1));
}

static void find_addr(EFI_PHYSICAL_ADDRESS *first,
		      EFI_PHYSICAL_ADDRESS *last,
		      EFI_PHYSICAL_ADDRESS min,
		      EFI_PHYSICAL_ADDRESS max,
		      size_t size, size_t align)
{
	EFI_MEMORY_DESCRIPTOR *map;
	UINT32 desc_ver;
	UINTN i, nr_entries, key, desc_sz;

	map = get_memory_map(&nr_entries, &key, &desc_sz, &desc_ver);
	if (!map)
		return;

	for (i = 0; i < nr_entries; i++) {
		EFI_MEMORY_DESCRIPTOR *m;
		EFI_PHYSICAL_ADDRESS best;
		UINT64 start, end;

		m = get_mem_desc((unsigned long)map, desc_sz, i);
		if (m->Type != EfiConventionalMemory)
			continue;

		if (m->NumberOfPages < EFI_SIZE_TO_PAGES(size))
			continue;

		start = m->PhysicalStart;
		end = m->PhysicalStart + (m->NumberOfPages << EFI_PAGE_SHIFT);
		if (first) {
			if (end < min)
				continue;

			/* What's the best address? */
			if (start < min && min < end)
				best = min;
			else
				best = m->PhysicalStart;

			start = round_up(best, align);
			if (start > max)
				continue;

			/* Have we run out of space in this region? */
			if (end < start || (start + size) > end)
				continue;

			if (start < *first)
				*first = start;
		}

		if (last) {
			if (start > max)
				continue;

			/* What's the best address? */
			if (start < max && max < end)
				best = max - size;
			else
				best = end - size;

			start = round_down(best, align);
			if (start < min || start < m->PhysicalStart)
				continue;

			if (start > *last)
				*last = start;
		}
	}

	FreePool(map);
}

/**
 * allocate_pages - Allocate memory pages from the system
 * @atype: type of allocation to perform
 * @mtype: type of memory to allocate
 * @num_pages: number of contiguous 4KB pages to allocate
 * @memory: used to return the address of allocated pages
 *
 * Allocate @num_pages physically contiguous pages from the system
 * memory and return a pointer to the base of the allocation in
 * @memory if the allocation succeeds. On success, the firmware memory
 * map is updated accordingly.
 *
 * If @atype is AllocateAddress then, on input, @memory specifies the
 * address at which to attempt to allocate the memory pages.
 */
static inline EFI_STATUS
allocate_pages(EFI_ALLOCATE_TYPE atype, EFI_MEMORY_TYPE mtype,
	       UINTN num_pages, EFI_PHYSICAL_ADDRESS *memory)
{
	return uefi_call_wrapper(BS->AllocatePages, 4, atype,
				 mtype, num_pages, memory);
}
/**
 * free_pages - Return memory allocated by allocate_pages() to the firmware
 * @memory: physical base address of the page range to be freed
 * @num_pages: number of contiguous 4KB pages to free
 *
 * On success, the firmware memory map is updated accordingly.
 */
static inline EFI_STATUS
free_pages(EFI_PHYSICAL_ADDRESS memory, UINTN num_pages)
{
	return uefi_call_wrapper(BS->FreePages, 2, memory, num_pages);
}

static EFI_STATUS allocate_addr(EFI_PHYSICAL_ADDRESS *addr, size_t size)
{
	UINTN npages = EFI_SIZE_TO_PAGES(size);

	return uefi_call_wrapper(BS->AllocatePages, 4,
				   AllocateAddress,
				   EfiLoaderData, npages,
				   addr);
}
/**
 * allocate_pool - Allocate pool memory
 * @type: the type of pool to allocate
 * @size: number of bytes to allocate from pool of @type
 * @buffer: used to return the address of allocated memory
 *
 * Allocate memory from pool of @type. If the pool needs more memory
 * pages are allocated from EfiConventionalMemory in order to grow the
 * pool.
 *
 * All allocations are eight-byte aligned.
 */
static inline EFI_STATUS
allocate_pool(EFI_MEMORY_TYPE type, UINTN size, void **buffer)
{
	return uefi_call_wrapper(BS->AllocatePool, 3, type, size, buffer);
}

/**
 * free_pool - Return pool memory to the system
 * @buffer: the buffer to free
 *
 * Return @buffer to the system. The returned memory is marked as
 * EfiConventionalMemory.
 */
static inline EFI_STATUS free_pool(void *buffer)
{
	return uefi_call_wrapper(BS->FreePool, 1, buffer);
}

static void free_addr(EFI_PHYSICAL_ADDRESS addr, size_t size)
{
	UINTN npages = EFI_SIZE_TO_PAGES(size);

	uefi_call_wrapper(BS->FreePages, 2, addr, npages);
}

/* cancel the established timer */
static EFI_STATUS cancel_timer(EFI_EVENT ev)
{
	return uefi_call_wrapper(BS->SetTimer, 3, ev, TimerCancel, 0);
}

/* Check if timer went off and update default timer counter */
void timer_handler(EFI_EVENT ev, VOID *ctx)
{
	__ms_timer += DEFAULT_MSTIMER_INC;
	++__jiffies;
}

/* Setup a default periodic timer */
static EFI_STATUS setup_default_timer(EFI_EVENT *ev)
{
	EFI_STATUS efi_status;

	*ev = NULL;
	efi_status = uefi_call_wrapper( BS->CreateEvent, 5, EVT_TIMER|EVT_NOTIFY_SIGNAL, TPL_NOTIFY, (EFI_EVENT_NOTIFY)timer_handler, NULL, ev);
	if (efi_status == EFI_SUCCESS) {
		efi_status = uefi_call_wrapper(BS->SetTimer, 3, *ev, TimerPeriodic, DEFAULT_TIMER_TICK_DURATION);
	}
	return efi_status;
}

/**
 * emalloc - Allocate memory with a strict alignment requirement
 * @size: size in bytes of the requested allocation
 * @align: the required alignment of the allocation
 * @addr: a pointer to the allocated address on success
 *
 * If we cannot satisfy @align we return 0.
 */
EFI_STATUS emalloc(UINTN size, UINTN align, EFI_PHYSICAL_ADDRESS *addr)
{
	UINTN i, nr_entries, map_key, desc_size;
	EFI_MEMORY_DESCRIPTOR *map_buf;
	UINTN d;
	UINT32 desc_version;
	EFI_STATUS err;
	UINTN nr_pages = EFI_SIZE_TO_PAGES(size);

	map_buf = get_memory_map(&nr_entries, &map_key,
				 &desc_size, &desc_version);
	if (!map_buf)
		goto fail;

	d = (UINTN)map_buf;

	for (i = 0; i < nr_entries; i++, d += desc_size) {
		EFI_MEMORY_DESCRIPTOR *desc;
		EFI_PHYSICAL_ADDRESS start, end, aligned;

		desc = (EFI_MEMORY_DESCRIPTOR *)d;
		if (desc->Type != EfiConventionalMemory)
			continue;

		if (desc->NumberOfPages < nr_pages)
			continue;

		start = desc->PhysicalStart;
		end = start + (desc->NumberOfPages << EFI_PAGE_SHIFT);

		/* Low-memory is super-precious! */
		if (end <= 1 << 20)
			continue;
		if (start < 1 << 20)
			start = (1 << 20);

		aligned = (start + align -1) & ~(align -1);

		if ((aligned + size) <= end) {
			err = allocate_pages(AllocateAddress, EfiLoaderData,
					     nr_pages, &aligned);
			if (err == EFI_SUCCESS) {
				*addr = aligned;
				break;
			}
		}
	}

	if (i == nr_entries)
		err = EFI_OUT_OF_RESOURCES;

	free_pool(map_buf);
fail:
	return err;
}
/**
 * efree - Return memory allocated with emalloc
 * @memory: the address of the emalloc() allocation
 * @size: the size of the allocation
 */
void efree(EFI_PHYSICAL_ADDRESS memory, UINTN size)
{
	UINTN nr_pages = EFI_SIZE_TO_PAGES(size);

	free_pages(memory, nr_pages);
}

/*
 * Check whether 'buf' contains a PE/COFF header and that the PE/COFF
 * file can be executed by this architecture.
 */
static bool valid_pecoff_image(char *buf)
{
    struct pe_header {
	uint16_t signature;
	uint8_t _pad[0x3a];
	uint32_t offset;
    } *pehdr = (struct pe_header *)buf;
    struct coff_header {
	uint32_t signature;
	uint16_t machine;
    } *chdr;

    if (pehdr->signature != 0x5a4d) {
	dprintf("Invalid MS-DOS header signature\n");
	return false;
    }

    if (!pehdr->offset || pehdr->offset > 512) {
	dprintf("Invalid PE header offset\n");
	return false;
    }

    chdr = (struct coff_header *)&buf[pehdr->offset];
    if (chdr->signature != 0x4550) {
	dprintf("Invalid PE header signature\n");
	return false;
    }

#if defined(__x86_64__)
    if (chdr->machine != 0x8664) {
	dprintf("Invalid PE machine field\n");
	return false;
    }
#else
    if (chdr->machine != 0x14c) {
	dprintf("Invalid PE machine field\n");
	return false;
    }
#endif

    return true;
}

/*
 * Boot a Linux kernel using the EFI boot stub handover protocol.
 *
 * This function will not return to its caller if booting the kernel
 * image succeeds. If booting the kernel image fails, a legacy boot
 * method should be attempted.
 */
static void handover_boot(struct linux_header *hdr, struct boot_params *bp)
{
    unsigned long address = hdr->code32_start + hdr->handover_offset;
    handover_func_t *func = efi_handover;

    dprintf("Booting kernel using handover protocol\n");

    /*
     * Ensure that the kernel is a valid PE32(+) file and that the
     * architecture of the file matches this version of Syslinux - we
     * can't mix firmware and kernel bitness (e.g. 32-bit kernel on
     * 64-bit EFI firmware) using the handover protocol.
     */
    if (!valid_pecoff_image((char *)hdr))
	return;

    if (hdr->version >= 0x20c) {
	if (hdr->xloadflags & XLF_EFI_HANDOVER_32)
	    func = efi_handover_32;

	if (hdr->xloadflags & XLF_EFI_HANDOVER_64)
	    func = efi_handover_64;
    }

    efi_console_restore();
    func(image_handle, ST, bp, address);
}

static int check_linux_header(struct linux_header *hdr)
{
	if (hdr->version < 0x205)
		hdr->relocatable_kernel = 0;

	/* FIXME: check boot sector signature */
	if (hdr->boot_flag != BOOT_SIGNATURE) {
		printf("Invalid Boot signature 0x%x, bailing out\n", hdr->boot_flag);
		return -1;
	}

	return 0;
}

static char *build_cmdline(char *str)
{
	EFI_PHYSICAL_ADDRESS addr;
	EFI_STATUS status;
	char *cmdline = NULL; /* internal, in efi_physical below 0x3FFFFFFF */

	/*
	 * The kernel expects cmdline to be allocated pretty low,
	 * Documentation/x86/boot.txt says,
	 *
	 *	"The kernel command line can be located anywhere
	 *	between the end of the setup heap and 0xA0000"
	 */
	addr = 0xA0000;
	status = allocate_pages(AllocateMaxAddress, EfiLoaderData,
			     EFI_SIZE_TO_PAGES(strlen(str) + 1),
			     &addr);
	if (status != EFI_SUCCESS) {
		printf("Failed to allocate memory for kernel command line, bailing out\n");
		return NULL;
	}
	cmdline = (char *)(UINTN)addr;
	memcpy(cmdline, str, strlen(str) + 1);
	return cmdline;
}

static int build_gdt(void)
{
	EFI_STATUS status;

	/* Allocate gdt consistent with the alignment for architecture */
	status = emalloc(gdt.limit, __SIZEOF_POINTER__ , (EFI_PHYSICAL_ADDRESS *)&gdt.base);
	if (status != EFI_SUCCESS) {
		printf("Failed to allocate memory for GDT, bailing out\n");
		return -1;
	}
	memset(gdt.base, 0x0, gdt.limit);

	/*
         * 4Gb - (0x100000*0x1000 = 4Gb)
         * base address=0
         * code read/exec
         * granularity=4096, 386 (+5th nibble of limit)
         */
        gdt.base[2] = 0x00cf9a000000ffff;

        /*
         * 4Gb - (0x100000*0x1000 = 4Gb)
         * base address=0
         * data read/write
         * granularity=4096, 386 (+5th nibble of limit)
         */
        gdt.base[3] = 0x00cf92000000ffff;

        /* Task segment value */
        gdt.base[4] = 0x0080890000000000;

	return 0;
}

/*
 * Callers use ->ramdisk_size to check whether any memory was
 * allocated (and therefore needs free'ing). The return value indicates
 * hard error conditions, such as failing to alloc memory for the
 * ramdisk image. Having no initramfs is not an error.
 */
static int handle_ramdisks(struct linux_header *hdr,
			   struct initramfs *initramfs)
{
	EFI_PHYSICAL_ADDRESS last;
	struct initramfs *ip;
	EFI_STATUS status;
	addr_t irf_size;
	addr_t next_addr, len, pad;

	hdr->ramdisk_image = 0;
	hdr->ramdisk_size = 0;

	/*
	 * Figure out the size of the initramfs, and where to put it.
	 * We should put it at the highest possible address which is
	 * <= hdr->initrd_addr_max, which fits the entire initramfs.
	 */
	irf_size = initramfs_size(initramfs);	/* Handles initramfs == NULL */
	if (!irf_size)
		return 0;

	last = 0;
	find_addr(NULL, &last, 0x1000, hdr->initrd_addr_max,
		  irf_size, INITRAMFS_MAX_ALIGN);
	if (last)
		status = allocate_addr(&last, irf_size);

	if (!last || status != EFI_SUCCESS) {
		printf("Failed to allocate initramfs memory, bailing out\n");
		return -1;
	}

	hdr->ramdisk_image = (uint32_t)last;
	hdr->ramdisk_size = irf_size;

	/* Copy initramfs into allocated memory */
	for (ip = initramfs->next; ip->len; ip = ip->next) {
		len = ip->len;
		next_addr = last + len;

		/*
		 * If this isn't the last entry, extend the
		 * zero-pad region to enforce the alignment of
		 * the next chunk.
		 */
		if (ip->next->len) {
			pad = -next_addr & (ip->next->align - 1);
			len += pad;
			next_addr += pad;
		}

		if (ip->data_len)
			memcpy((void *)(UINTN)last, ip->data, ip->data_len);

		if (len > ip->data_len)
			memset((void *)(UINTN)(last + ip->data_len), 0,
			       len - ip->data_len);

		last = next_addr;
	}
	return 0;
}

static int exit_boot(struct boot_params *bp)
{
	struct e820_entry *e820buf, *e;
	EFI_MEMORY_DESCRIPTOR *map;
	EFI_STATUS status;
	uint32_t e820_type;
	UINTN i, nr_entries, key, desc_sz;
	UINT32 desc_ver;

	/* Build efi memory map */
	map = get_memory_map(&nr_entries, &key, &desc_sz, &desc_ver);
	if (!map)
		return -1;

	bp->efi.memmap = (uint32_t)(unsigned long)map;
	bp->efi.memmap_size = nr_entries * desc_sz;
	bp->efi.systab = (uint32_t)(unsigned long)ST;
	bp->efi.desc_size = desc_sz;
	bp->efi.desc_version = desc_ver;
#if defined(__x86_64__)
        bp->efi.systab_hi = ((unsigned long)ST) >> 32;
        bp->efi.memmap_hi = ((unsigned long)map) >> 32;
#endif


	/*
	 * Even though 'memmap' contains the memory map we provided
	 * previously in efi_scan_memory(), we should recalculate the
	 * e820 map because it will most likely have changed in the
	 * interim.
	 */
	e = e820buf = bp->e820_map;
	for (i = 0; i < nr_entries && i < E820MAX; i++) {
		struct e820_entry *prev = NULL;

		if (e > e820buf)
			prev = e - 1;

		map = get_mem_desc(bp->efi.memmap, desc_sz, i);
		e->start = map->PhysicalStart;
		e->len = map->NumberOfPages << EFI_PAGE_SHIFT;

		switch (map->Type) {
		case EfiReservedMemoryType:
                case EfiRuntimeServicesCode:
                case EfiRuntimeServicesData:
                case EfiMemoryMappedIO:
                case EfiMemoryMappedIOPortSpace:
                case EfiPalCode:
                        e820_type = E820_RESERVED;
                        break;

                case EfiUnusableMemory:
                        e820_type = E820_UNUSABLE;
                        break;

                case EfiACPIReclaimMemory:
                        e820_type = E820_ACPI;
                        break;

                case EfiLoaderCode:
                case EfiLoaderData:
                case EfiBootServicesCode:
                case EfiBootServicesData:
                case EfiConventionalMemory:
			e820_type = E820_RAM;
			break;

		case EfiACPIMemoryNVS:
			e820_type = E820_NVS;
			break;
		default:
			continue;
		}

		e->type = e820_type;

		/* Check for adjacent entries we can merge. */
		if (prev && (prev->start + prev->len) == e->start &&
		    prev->type == e->type)
			prev->len += e->len;
		else
			e++;
	}

	bp->e820_entries = e - e820buf;

	status = uefi_call_wrapper(BS->ExitBootServices, 2, image_handle, key);
	if (status != EFI_SUCCESS) {
		printf("Failed to exit boot services: 0x%016lx\n", status);
		FreePool(map);
		return -1;
	}

	return 0;
}

/* efi_boot_linux: 
 * Boots the linux kernel using the image and parameters to boot with.
 * The EFI boot loader is reworked taking the cue from
 * http://git.kernel.org/?p=boot/efilinux/efilinux.git on the need to
 * cap key kernel data structures at * 0x3FFFFFFF.
 * The kernel image, kernel command line and boot parameter block are copied
 * into allocated memory areas that honor the address capping requirement
 * prior to kernel handoff. 
 *
 * FIXME
 * Can we move this allocation requirement to com32 linux loader in order
 * to avoid double copying kernel image?
 */
int efi_boot_linux(void *kernel_buf, size_t kernel_size,
		   struct initramfs *initramfs,
		   struct setup_data *setup_data,
		   char *cmdline)
{
	struct linux_header *hdr;
	struct boot_params *bp;
	EFI_STATUS status;
	EFI_PHYSICAL_ADDRESS addr, pref_address, kernel_start = 0;
	UINT64 setup_sz, init_size = 0;
	char *_cmdline;

	if (check_linux_header(kernel_buf))
		goto bail;

	/* allocate for boot parameter block */
	addr = 0x3FFFFFFF;
	status = allocate_pages(AllocateMaxAddress, EfiLoaderData,
			     BOOT_PARAM_BLKSIZE, &addr);
	if (status != EFI_SUCCESS) {
		printf("Failed to allocate memory for kernel boot parameter block, bailing out\n");
		goto bail;
	}

	bp = (struct boot_params *)(UINTN)addr;

	memset((void *)bp, 0x0, BOOT_PARAM_BLKSIZE);
	/* Copy the first two sectors to boot_params */
	memcpy((char *)bp, kernel_buf, 2 * 512);
	hdr = (struct linux_header *)bp;

	setup_sz = (hdr->setup_sects + 1) * 512;
	if (hdr->version >= 0x20a) {
		pref_address = hdr->pref_address;
		init_size = hdr->init_size;
	} else {
		pref_address = 0x100000;

		/*
		 * We need to account for the fact that the kernel
		 * needs room for decompression, otherwise we could
		 * end up trashing other chunks of allocated memory.
		 */
		init_size = (kernel_size - setup_sz) * 3;
	}
	hdr->type_of_loader = SYSLINUX_EFILDR;	/* SYSLINUX boot loader module */
	_cmdline = build_cmdline(cmdline);
	if (!_cmdline)
		goto bail;

	hdr->cmd_line_ptr = (UINT32)(UINTN)_cmdline;

	addr = pref_address;
	status = allocate_pages(AllocateAddress, EfiLoaderData,
			     EFI_SIZE_TO_PAGES(init_size), &addr);
	if (status != EFI_SUCCESS) {
		/*
		 * We failed to allocate the preferred address, so
		 * just allocate some memory and hope for the best.
		 */
		if (!hdr->relocatable_kernel) {
			printf("Cannot relocate kernel, bailing out\n");
			goto bail;
		}

		status = emalloc(init_size, hdr->kernel_alignment, &addr);
		if (status != EFI_SUCCESS) {
			printf("Failed to allocate memory for kernel image, bailing out\n");
			goto free_map;
		}
	}
	kernel_start = addr;
	/* FIXME: we copy the kernel into the physical memory allocated here
	 * The syslinux kernel image load elsewhere could allocate the EFI memory from here
	 * prior to copying kernel and save an extra copy
	 */
	memcpy((void *)(UINTN)kernel_start, kernel_buf+setup_sz, kernel_size-setup_sz);

	hdr->code32_start = (UINT32)((UINT64)kernel_start);

	dprintf("efi_boot_linux: kernel_start 0x%x kernel_size 0x%x initramfs 0x%x setup_data 0x%x cmdline 0x%x\n",
	kernel_start, kernel_size, initramfs, setup_data, _cmdline);

	if (handle_ramdisks(hdr, initramfs))
		goto free_map;

	/* Attempt to use the handover protocol if available */
	if (hdr->version >= 0x20b && hdr->handover_offset)
		handover_boot(hdr, bp);

	setup_screen(&bp->screen_info);

	if (build_gdt())
		goto free_map;

	dprintf("efi_boot_linux: setup_sects %d kernel_size %d\n", hdr->setup_sects, kernel_size);

	efi_console_restore();

	if (exit_boot(bp))
		goto free_map;

	memcpy(&bp->efi.load_signature, EFI_LOAD_SIG, sizeof(uint32_t));

	asm volatile ("lidt %0" :: "m" (idt));
	asm volatile ("lgdt %0" :: "m" (gdt));

	kernel_jump(kernel_start, bp);

	/* NOTREACHED */

free_map:
	if (_cmdline)
		efree((EFI_PHYSICAL_ADDRESS)(unsigned long)_cmdline,
		      strlen(_cmdline) + 1);

	if (bp)
		efree((EFI_PHYSICAL_ADDRESS)(unsigned long)bp,
		       BOOT_PARAM_BLKSIZE);
	if (kernel_start) efree(kernel_start, init_size);
	if (hdr->ramdisk_size)
		free_addr(hdr->ramdisk_image, hdr->ramdisk_size);
bail:
	return -1;
}

extern struct disk *efi_disk_init(EFI_HANDLE);
extern void serialcfg(uint16_t *, uint16_t *, uint16_t *);

extern struct vesa_ops efi_vesa_ops;

struct mem_ops efi_mem_ops = {
	.malloc = efi_malloc,
	.realloc = efi_realloc,
	.free = efi_free,
};

struct firmware efi_fw = {
	.init = efi_init,
	.disk_init = efi_disk_init,
	.o_ops = &efi_ops,
	.i_ops = &efi_iops,
	.get_serial_console_info = serialcfg,
	.adv_ops = &efi_adv_ops,
	.boot_linux = efi_boot_linux,
	.vesa = &efi_vesa_ops,
	.mem = &efi_mem_ops,
};

static inline void syslinux_register_efi(void)
{
	firmware = &efi_fw;
}

extern void init(void);
extern const struct fs_ops vfat_fs_ops;
extern const struct fs_ops pxe_fs_ops;

char free_high_memory[4096];

extern char __bss_start[];
extern char __bss_end[];

static void efi_setcwd(CHAR16 *dp)
{
	CHAR16 *c16;
	char *c8;
	int i, j;

	/* Search for the start of the last path component */
	for (i = StrLen(dp) - 1; i >= 0; i--) {
		if (dp[i] == '\\' || dp[i] == '/')
			break;
	}

	if (i < 0 || i > CURRENTDIR_MAX) {
		dp = L"\\";
		i = 1;
	}

	c8 = CurrentDirName;
	c16 = dp;

	for (j = 0; j < i; j++) {
		if (*c16 == '\\') {
			*c8++ = '/';
			c16++;
		} else
			*c8++ = *c16++;
	}

	*c8 = '\0';
}

EFI_STATUS efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *table)
{
	EFI_PXE_BASE_CODE *pxe;
	EFI_LOADED_IMAGE *info;
	EFI_STATUS status = EFI_SUCCESS;
	const struct fs_ops *ops[] = { NULL, NULL };
	unsigned long len = (unsigned long)__bss_end - (unsigned long)__bss_start;
	static struct efi_disk_private priv;
	SIMPLE_INPUT_INTERFACE *in;
	EFI_INPUT_KEY key;
	EFI_EVENT timer_ev;

	memset(__bss_start, 0, len);
	InitializeLib(image, table);

	image_handle = image;
	syslinux_register_efi();

	efi_console_save();
	init();

	status = uefi_call_wrapper(BS->HandleProtocol, 3, image,
				   &LoadedImageProtocol, (void **)&info);
	if (status != EFI_SUCCESS) {
		Print(L"Failed to lookup LoadedImageProtocol\n");
		goto out;
	}

	status = uefi_call_wrapper(BS->HandleProtocol, 3, info->DeviceHandle,
				   &PxeBaseCodeProtocol, (void **)&pxe);
	if (status != EFI_SUCCESS) {
		/*
		 * Use device handle to set up the volume root to
		 * proceed with ADV init.
		 */
		if (EFI_ERROR(efi_set_volroot(info->DeviceHandle))) {
			Print(L"Failed to locate root device to prep for ");
			Print(L"file operations & ADV initialization\n");
			goto out;
		}

		efi_derivative(SYSLINUX_FS_SYSLINUX);
		ops[0] = &vfat_fs_ops;
	} else {
		efi_derivative(SYSLINUX_FS_PXELINUX);
		ops[0] = &pxe_fs_ops;
	}

	/* setup timer for boot menu system support */
	status = setup_default_timer(&timer_ev);
	if (status != EFI_SUCCESS) {
		Print(L"Failed to set up EFI timer support, bailing out\n");
		goto out;
	}

	/* TODO: once all errors are captured in efi_errno, bail out if necessary */

	priv.dev_handle = info->DeviceHandle;

	/*
	 * Set the current working directory, which should be the
	 * directory that syslinux.efi resides in.
	 */
	efi_setcwd(DevicePathToStr(info->FilePath));

	fs_init(ops, (void *)&priv);

	/*
	 * There may be pending user input that wasn't processed by
	 * whatever application invoked us. Consume and discard that
	 * data now.
	 */
	in = ST->ConIn;
	do {
		status = uefi_call_wrapper(in->ReadKeyStroke, 2, in, &key);
	} while (status != EFI_NOT_READY);

	if (!setjmp(load_error_buf))
		load_env32(NULL);

	/* load_env32() failed.. cancel timer and bailout */
	status = cancel_timer(timer_ev);
	if (status != EFI_SUCCESS)
		Print(L"Failed to cancel EFI timer: %x\n", status);

	/*
	 * Tell the firmware that Syslinux failed to load.
	 */
	status = EFI_LOAD_ERROR;
out:
	efi_console_restore();
	return status;
}
