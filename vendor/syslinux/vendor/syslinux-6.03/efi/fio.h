#ifndef _H_EFI_FIO_
#define _H_EFI_FIO_

/*
 * Friendly interfaces for EFI file I/O and various EFI support functions
 */

/* MAX_EFI_ARGS - command line args for EFI executable
 * WS(c16) 	- check for CHAR16 white space
 */
#define MAX_EFI_ARGS		64
#define WS(c16)         (c16 == L' ' || c16 == CHAR_TAB)

/* VPrint is not in export declarations in gnu-efi lib yet
 * although it is a global function; declare it here
 */
extern UINTN
VPrint (
    IN CHAR16   *fmt,
    va_list     args
    );

extern EFI_STATUS efi_errno;

void efi_memcpy(unsigned char *dst, unsigned char *src, size_t len);
void efi_memmove(unsigned char *dst, unsigned char *src, size_t len);
void efi_memset(unsigned char *dst, unsigned char val, size_t len);
void *efi_alloc(int size);
void efi_free(void *ptr);
void efi_perror(CHAR16 *str);
void efi_printerr(IN CHAR16 *fmt, ...);
void efi_printout(IN CHAR16 *fmt, ...);
EFI_STATUS efi_set_volroot(EFI_HANDLE device_handle);
EFI_FILE_HANDLE efi_open(CHAR16 *file, UINT64 mode);
void efi_close(EFI_FILE_HANDLE fd);
void efi_sync(EFI_FILE_HANDLE fd);
size_t efi_xpread(EFI_FILE_HANDLE fd, void *buf, size_t count, off_t offset);
size_t efi_xpwrite(EFI_FILE_HANDLE fd, void *buf, size_t count, off_t offset);
int efi_fstat(EFI_FILE_HANDLE fd, EFI_FILE_INFO *st);
void efi_set_attributes(EFI_FILE_HANDLE fd);
void efi_clear_attributes(EFI_FILE_HANDLE fd);

#endif
