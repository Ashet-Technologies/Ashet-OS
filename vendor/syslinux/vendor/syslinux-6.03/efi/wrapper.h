#ifndef EFI_WRAPPER_H
#define EFI_WRAPPER_H

#define MSDOS_SIGNATURE	0x5a4d
#define PE_SIGNATURE	0x4550
#define PE32_FORMAT	0x10b
#define PE32P_FORMAT	0x20b	/* PE32+ */

#define IMAGE_FILE_MACHINE_I386			0x14c
#define IMAGE_FILE_MACHINE_X86_64		0x8664
#define IMAGE_FILE_EXECUTABLE_IMAGE		0x0002
#define IMAGE_FILE_LINE_NUMBERS_STRIPPED	0x0004
#define IMAGE_FILE_32BIT_MACHINE		0x0100
#define IMAGE_FILE_DEBUG_STRIPPED		0x0200

#define IMAGE_SUBSYSTEM_EFI_APPLICATION		0x0a

#define IMAGE_SCN_CNT_CODE		0x00000020
#define IMAGE_SCN_CNT_INITIALIZED_DATA	0x00000040
#define IMAGE_SCN_ALIGN_1BYTES		0x00100000
#define IMAGE_SCN_ALIGN_16BYTES		0x00500000
#define IMAGE_SCN_MEM_DISCARDABLE	0x02000000
#define IMAGE_SCN_MEM_EXECUTE		0x20000000
#define IMAGE_SCN_MEM_READ		0x40000000

#define __packed	__attribute__((packed))
#define OFFSETOF(t,m)	((size_t)&((t *)0)->m)

struct header {
	__uint16_t msdos_signature;
	__uint8_t _pad1[0x16];
	__uint16_t relocs_ptr;
	__uint8_t __pad2[0x3c - 0x1a];
	__uint32_t pe_hdr;
	__uint16_t pe_signature;
	__uint16_t _pad2;
} __packed;

/* FIXME: when setting up coff_hdr, set up optional_hdr_sz
 * based on PE32 or PE32+ format
 */
/*
 * COFF header
 */
struct coff_hdr {
	__uint16_t arch;
	__uint16_t nr_sections;
	__uint32_t timedatestamp;
	__uint32_t symtab;
	__uint32_t nr_syms;
	__uint16_t optional_hdr_sz;
	__uint16_t characteristics;
} __packed;

struct optional_hdr {
	__uint16_t format;
	__uint8_t major_linker_version;
	__uint8_t minor_linker_version;
	__uint32_t code_sz;
	__uint32_t initialized_data_sz;
	__uint32_t uninitialized_data_sz;
	__uint32_t entry_point;
	__uint32_t base_code;
	__uint32_t data;
} __packed;

/* For PE32+, the optional_header does NOT have
 * data after base_code
 */
struct optional_hdr_pe32p {
	__uint16_t format;
	__uint8_t major_linker_version;
	__uint8_t minor_linker_version;
	__uint32_t code_sz;
	__uint32_t initialized_data_sz;
	__uint32_t uninitialized_data_sz;
	__uint32_t entry_point;
	__uint32_t base_code;
} __packed;
/*
 * Extra header fields
 */
struct extra_hdr {
	__uint32_t image_base;
	__uint32_t section_align;
	__uint32_t file_align;
	__uint16_t major_os_version;
	__uint16_t minor_os_version;
	__uint16_t major_image_version;
	__uint16_t minor_image_version;
	__uint16_t major_subsystem_version;
	__uint16_t minor_subsystem_version;
	__uint32_t win32_version;
	__uint32_t image_sz;
	__uint32_t headers_sz;
	__uint32_t checksum;
	__uint16_t subsystem;
	__uint16_t dll_characteristics;
	__uint32_t stack_reserve_sz;
	__uint32_t stack_commit_sz;
	__uint32_t heap_reserve_sz;
	__uint32_t heap_commit_sz;
	__uint32_t loader_flags;
	__uint32_t rva_and_sizes_nr;
	struct {
		__uint64_t export_table;
		__uint64_t import_table;
		__uint64_t resource_table;
		__uint64_t exception_table;
		__uint64_t certification_table;
		__uint64_t base_relocation_table;
	} data_directory;
} __packed;

/* Extra header for PE32+ format 
 * FIXME: There are additional fields in Microsoft PE COFF v8
 */

struct extra_hdr_pe32p {
	__uint64_t image_base;
	__uint32_t section_align;
	__uint32_t file_align;
	__uint16_t major_os_version;
	__uint16_t minor_os_version;
	__uint16_t major_image_version;
	__uint16_t minor_image_version;
	__uint16_t major_subsystem_version;
	__uint16_t minor_subsystem_version;
	__uint32_t win32_version;
	__uint32_t image_sz;
	__uint32_t headers_sz;
	__uint32_t checksum;
	__uint16_t subsystem;
	__uint16_t dll_characteristics;
	__uint64_t stack_reserve_sz;
	__uint64_t stack_commit_sz;
	__uint64_t heap_reserve_sz;
	__uint64_t heap_commit_sz;
	__uint32_t loader_flags;
	__uint32_t rva_and_sizes_nr;
	struct {
		__uint64_t export_table;
		__uint64_t import_table;
		__uint64_t resource_table;
		__uint64_t exception_table;
		__uint64_t certification_table;
		__uint64_t base_relocation_table;
	} data_directory;
} __packed;

struct section {
	__uint8_t name[8];
	__uint32_t virtual_sz;
	__uint32_t virtual_address;
	__uint32_t raw_data_sz;
	__uint32_t raw_data;
	__uint32_t relocs;
	__uint32_t line_numbers;
	__uint16_t relocs_nr;
	__uint16_t line_numbers_nr;
	__uint32_t characteristics;
} __packed;

struct coff_reloc {
	__uint32_t virtual_address;
	__uint32_t symtab_index;
	__uint16_t type;
};

#endif /* EFI_WRAPPER_H */
