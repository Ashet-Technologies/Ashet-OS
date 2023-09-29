#ifndef SYSDUMP_H
#define SYSDUMP_H

#include <libupload/upload_backend.h>

void dump_memory_map(struct upload_backend *);
void snapshot_lowmem(void);
void dump_memory(struct upload_backend *);
void dump_dmi(struct upload_backend *);
void dump_acpi(struct upload_backend *);
void dump_cpuid(struct upload_backend *);
void dump_pci(struct upload_backend *);
void dump_vesa_tables(struct upload_backend *);

#endif /* SYSDUMP_H */
