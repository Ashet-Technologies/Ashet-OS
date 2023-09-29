#ifndef _SYSLINUX_EFI_H
#define _SYSLINUX_EFI_H

#include <syslinux/config.h>
#include <core.h>
#include <sys/types.h>	/* needed for off_t */
//#include <syslinux/version.h> /* avoid redefinition of __STDC_VERSION__ */

/*
 * gnu-efi >= 3.0s enables GNU_EFI_USE_MS_ABI by default, which means
 * that we must also enable it if supported by the compiler. Note that
 * failing to enable GNU_EFI_USE_MS_ABI if gnu-efi was compiled with
 * it on will result in undefined references to uefi_call_wrapper().
 *
 * The reason we don't attempt to check the version of gnu-efi we're
 * building against is because there's no harm in turning it on for
 * older versions - it will just be ignored.
 */
#if defined(__GNUC__) && (__GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 7))
  #define GNU_EFI_USE_MS_ABI 1
#endif

#include <efi.h>
#include <efilib.h>
#include <efistdarg.h>

/* Delay for 100 ms */
#define EFI_NOMAP_PRINT_DELAY	100
/* We should keep EFI_NOMAP_PRINT_COUNT at 10 to limit flooding the console */
#define EFI_NOMAP_PRINT_COUNT	10

struct efi_disk_private {
	EFI_HANDLE dev_handle;
	EFI_BLOCK_IO *bio;
	EFI_DISK_IO *dio;
};

struct efi_binding {
    EFI_SERVICE_BINDING *binding;
    EFI_HANDLE parent;
    EFI_HANDLE child;
    EFI_HANDLE this;
};

extern EFI_HANDLE image_handle;

struct screen_info;
extern void setup_screen(struct screen_info *);

extern void efi_write_char(uint8_t, uint8_t);

enum heap;
extern void *efi_malloc(size_t, enum heap, size_t);
extern void *efi_realloc(void *, size_t);
extern void efi_free(void *);

extern struct efi_binding *efi_create_binding(EFI_GUID *, EFI_GUID *);
extern void efi_destroy_binding(struct efi_binding *, EFI_GUID *);

static inline EFI_STATUS
efi_setup_event(EFI_EVENT *ev, EFI_EVENT_NOTIFY func, void *ctx)
{
    EFI_STATUS status;

    status = uefi_call_wrapper(BS->CreateEvent, 5, EVT_NOTIFY_SIGNAL,
			       TPL_CALLBACK, func, ctx, ev);
    return status;
}

extern void efi_derivative(enum syslinux_filesystem fs);

struct boot_params;
typedef void (handover_func_t)(void *, EFI_SYSTEM_TABLE *,
			       struct boot_params *, unsigned long);

handover_func_t efi_handover_32;
handover_func_t efi_handover_64;
handover_func_t efi_handover;

extern void efi_console_save(void);
extern void efi_console_restore(void);

#endif /* _SYSLINUX_EFI_H */
