/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Erwan Velu - All Rights Reserved
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * -----------------------------------------------------------------------
 */

#ifndef DEFINE_HDT_COMMON_H
#define DEFINE_HDT_COMMON_H
#include <stdio.h>
#include <syslinux/pxe.h>
#include <console.h>
#include <consoles.h>
#include <syslinux/vesacon.h>
#include "sys/pci.h"

#include <disk/bootloaders.h>
#include <disk/errno_disk.h>
#include <disk/error.h>
#include <disk/geom.h>
#include <disk/mbrs.h>
#include <disk/msdos.h>
#include <disk/partition.h>
#include <disk/swsusp.h>
#include <disk/read.h>

#include "cpuid.h"
#include "dmi/dmi.h"
#include "hdt-ata.h"
#include <lib/sys/vesa/vesa.h>
#include <vpd/vpd.h>
#include <libansi.h>
#include <acpi/acpi.h>
#include <libupload/upload_backend.h>

/* This two values are used for switching for the menu to the CLI mode */
#define HDT_SWITCH_TO_CLI "hdt_switch_to_cli"
#define HDT_DUMP "hdt_dump"
#define HDT_RETURN_TO_CLI 100
#define MAX_VESA_MODES 255

/* This value is used for rebooting from the menu mode */
#define HDT_REBOOT "hdt_reboot"

/* The maximum number of commands we can process */
#define MAX_NB_AUTO_COMMANDS 255
/* The maximum size of a command */
#define AUTO_COMMAND_SIZE 255
/* The char that separate two commands */
#define AUTO_SEPARATOR ";"
/* The char that surround the list of commands */
#define AUTO_DELIMITER '\'' 

/* Graphic to load in background when using the vesa mode */
#define CLI_DEFAULT_BACKGROUND "backgnd.png"

/* The maximum number of lines */
#define MAX_CLI_LINES 20
#define MAX_VESA_CLI_LINES 24

struct upload_backend *upload;

/* Defines if the cli is quiet*/
bool quiet;

/* Defines if the cli is totally silent*/
bool silent;

/* Defines if we must use the vesa mode */
bool vesamode;

/* Defines if we must use the menu mode */
bool menumode;

/* Defines if we are running the auto mode */
bool automode;

/* Defines the number of lines in the console
 * Default is 20 for a std console */
extern int max_console_lines;

extern int display_line_nb;
extern bool disable_more_printf;

#define pause_printf() do {\
       printf("--More--");\
       get_key(stdin, 0);\
       printf("\033[2K\033[1G\033[1F\n");\
} while (0);

/* The brokeness of that macro is that
 * it assumes that __VA_ARGS__ contains
 * one \n (and only one)
 */
#define more_printf(...) do {\
 if (__likely(!silent)) {\
  if (__likely(!disable_more_printf)) {\
   if (display_line_nb == max_console_lines) {\
    display_line_nb=0;\
    printf("\n--More--");\
    get_key(stdin, 0);\
    printf("\033[2K\033[1G\033[1F");\
   }\
   display_line_nb++;\
  }\
  printf(__VA_ARGS__);\
 }\
} while (0);

/* Display CPU registers for debugging purposes */
static inline void printregs(const com32sys_t * r)
{
    printf("eflags = %08x  ds = %04x  es = %04x  fs = %04x  gs = %04x\n"
	   "eax = %08x  ebx = %08x  ecx = %08x  edx = %08x\n"
	   "ebp = %08x  esi = %08x  edi = %08x  esp = %08x\n",
	   r->eflags.l, r->ds, r->es, r->fs, r->gs,
	   r->eax.l, r->ebx.l, r->ecx.l, r->edx.l,
	   r->ebp.l, r->esi.l, r->edi.l, r->_unused_esp.l);
}

struct s_pxe {
    uint16_t vendor_id;
    uint16_t product_id;
    uint16_t subvendor_id;
    uint16_t subproduct_id;
    uint8_t rev;
    uint8_t pci_bus;
    uint8_t pci_dev;
    uint8_t pci_func;
    uint8_t base_class;
    uint8_t sub_class;
    uint8_t prog_intf;
    uint8_t nictype;
    char mac_addr[18];		/* The current mac address */
    uint8_t ip_addr[4];
    pxe_bootp_t dhcpdata;	/* The dhcp answer */
    struct pci_device *pci_device;	/* The matching pci device */
    uint8_t pci_device_pos;	/* It position in our pci sorted list */
};

struct s_vesa_mode_info {
    struct vesa_mode_info mi;
    uint16_t mode;
};

struct s_vesa {
    uint8_t major_version;
    uint8_t minor_version;
    struct s_vesa_mode_info vmi[MAX_VESA_MODES];
    uint8_t vmi_count;
    uint16_t total_memory;
    char vendor[256];
    char product[256];
    char product_revision[256];
    uint16_t software_rev;
};

struct s_hardware {
    s_dmi dmi;			/* DMI table */
    s_cpu cpu;			/* CPU information */
    uint8_t physical_cpu_count; /* Number of physical cpu */
    s_vpd vpd;			/* VPD information */
    s_acpi acpi;
    struct pci_domain *pci_domain;	/* PCI Devices */
    struct driveinfo disk_info[256];	/* Disk Information */
    uint32_t mbr_ids[256];	/* MBR ids */
    int disks_count;		/* Number of detected disks */
    struct s_pxe pxe;
    struct s_vesa vesa;
    unsigned long detected_memory_size;	/* The detected memory size (in KB) */

    int pci_ids_return_code;
    int modules_pcimap_return_code;
    int modules_alias_return_code;
    int nb_pci_devices;
    bool is_dmi_valid;
    bool is_pxe_valid;
    bool is_vesa_valid;
    bool is_vpd_valid;
    bool is_acpi_valid;

    bool dmi_detection;		/* Does the dmi stuff has already been detected? */
    bool pci_detection;		/* Does the pci stuff has already been detected? */
    bool cpu_detection;		/* Does the cpu stuff has already been detected? */
    bool disk_detection;	/* Does the disk stuff has already been detected? */
    bool pxe_detection;		/* Does the pxe stuff has already been detected? */
    bool vesa_detection;	/* Does the vesa sutff have been already detected? */
    bool vpd_detection;		/* Does the vpd stuff has already been detected? */
    bool memory_detection;	/* Does the memory size got detected ?*/
    bool acpi_detection;	/* Does the acpi got detected ?*/

    char syslinux_fs[22];
    const struct syslinux_version *sv;
    char modules_pcimap_path[255];
    char modules_alias_path[255];
    char pciids_path[255];
    char dump_path[255]; /* Dump path on the tftp server */
    char dump_filename[255]; /* Dump filename on the tftp server */
    char tftp_ip[255];   /* IP address of tftp server (dump mode) */
    char memtest_label[255];
    char auto_label[AUTO_COMMAND_SIZE];
    char vesa_background[255];
    char postexec[255];
};

void reset_more_printf(void);
const char *find_argument(const char **argv, const char *argument);
char *remove_spaces(char *p);
char *remove_trailing_lf(char *p);
char *skip_spaces(char *p);
char *del_multi_spaces(char *p);
int detect_dmi(struct s_hardware *hardware);
int detect_vpd(struct s_hardware *hardware);
void detect_disks(struct s_hardware *hardware);
void detect_pci(struct s_hardware *hardware);
void cpu_detect(struct s_hardware *hardware);
int detect_pxe(struct s_hardware *hardware);
void init_hardware(struct s_hardware *hardware);
void clear_screen(void);
void detect_syslinux(struct s_hardware *hardware);
int detect_acpi(struct s_hardware *hardware);
void detect_parameters(const int argc, const char *argv[],
		       struct s_hardware *hardware);
int detect_vesa(struct s_hardware *hardware);
void detect_memory(struct s_hardware *hardware);
void init_console(struct s_hardware *hardware);
void detect_hardware(struct s_hardware *hardware);
void dump(struct s_hardware *hardware);
#endif
