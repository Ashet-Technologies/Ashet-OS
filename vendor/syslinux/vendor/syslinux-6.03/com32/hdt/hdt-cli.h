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

#ifndef DEFINE_HDT_CLI_H
#define DEFINE_HDT_CLI_H
#include <stdio.h>
#include <getkey.h>
#include <dprintf.h>

#include "hdt-common.h"

#define MAX_LINE_SIZE 256

#define CLI_SPACE " "
#define CLI_LF "\n"
#define CLI_MENU "menu"
#define CLI_CLEAR "clear"
#define CLI_EXIT "exit"
#define CLI_HELP "help"
#define CLI_REBOOT "reboot"
#define CLI_SHOW "show"
#define CLI_SET "set"
#define CLI_MODE "mode"
#define CLI_HDT  "hdt"
#define CLI_PCI  "pci"
#define CLI_PXE  "pxe"
#define CLI_KERNEL "kernel"
#define CLI_SYSLINUX "syslinux"
#define CLI_VESA "vesa"
#define CLI_SUMMARY "summary"
#define CLI_COMMANDS "commands"
#define CLI_DMI  "dmi"
#define CLI_CPU  "cpu"
#define CLI_DISK  "disk"
#define CLI_SHOW_LIST "list"
#define CLI_IRQ "irq"
#define CLI_MODES "modes"
#define CLI_VPD  "vpd"
#define CLI_MEMORY  "memory"
#define CLI_ACPI "acpi"
#define CLI_ENABLE "enable"
#define CLI_DISABLE "disable"
#define CLI_DUMP "dump"
#define CLI_SAY "say"
#define CLI_DISPLAY "display"
#define CLI_SLEEP "sleep"

typedef enum {
    INVALID_MODE,
    EXIT_MODE,
    HDT_MODE,
    PCI_MODE,
    DMI_MODE,
    CPU_MODE,
    PXE_MODE,
    KERNEL_MODE,
    SYSLINUX_MODE,
    VESA_MODE,
    DISK_MODE,
    VPD_MODE,
    MEMORY_MODE,
    ACPI_MODE
} cli_mode_t;

#define PROMPT_SIZE 32
#define MAX_HISTORY_SIZE 32
#define INPUT hdt_cli.history[hdt_cli.history_pos]
struct s_cli {
    cli_mode_t mode;
    char prompt[PROMPT_SIZE];
    uint8_t cursor_pos;
    char history[MAX_HISTORY_SIZE+1][MAX_LINE_SIZE];
    int history_pos;
    int max_history_pos;
};
struct s_cli hdt_cli;

/* Describe a cli mode */
struct cli_mode_descr {
    const unsigned int mode;
    const char *name;
    /* Handle 1-token commands */
    struct cli_module_descr *default_modules;
    /* Handle show <module> <args> */
    struct cli_module_descr *show_modules;
    /* Handle set <module> <args> */
    struct cli_module_descr *set_modules;
};

/* Describe a subset of commands in a module (default, show, set, ...) */
struct cli_module_descr {
    struct cli_callback_descr *modules;
    void (*default_callback) (int argc, char **argv,
			      struct s_hardware * hardware);
};

/* Describe a callback (belongs to a mode and a module) */
struct cli_callback_descr {
    const char *name;
    void (*exec) (int argc, char **argv, struct s_hardware * hardware);
    bool nomodule;
};

/* Manage aliases */
#define MAX_ALIASES 2
struct cli_alias {
    const char *command;	/* Original command */
    const int nb_aliases;	/* Size of aliases array */
    const char **aliases;	/* List of aliases */
};

/* List of implemented modes */
extern struct cli_mode_descr *list_modes[];
struct cli_mode_descr hdt_mode;
struct cli_mode_descr dmi_mode;
struct cli_mode_descr syslinux_mode;
struct cli_mode_descr pxe_mode;
struct cli_mode_descr kernel_mode;
struct cli_mode_descr cpu_mode;
struct cli_mode_descr pci_mode;
struct cli_mode_descr vesa_mode;
struct cli_mode_descr disk_mode;
struct cli_mode_descr vpd_mode;
struct cli_mode_descr memory_mode;
struct cli_mode_descr acpi_mode;

/* cli helpers */
void find_cli_mode_descr(cli_mode_t mode, struct cli_mode_descr **mode_found);
void find_cli_callback_descr(const char *module_name,
			     struct cli_module_descr *modules_list,
			     struct cli_callback_descr **module_found);
cli_mode_t mode_s_to_mode_t(char *name);

void set_mode(cli_mode_t mode, struct s_hardware *hardware);
void start_cli_mode(struct s_hardware *hardware);
void start_auto_mode(struct s_hardware *hardware);
void main_show(char *item, struct s_hardware *hardware);

#define CLI_HISTORY "history"
void print_history(int argc, char **argv, struct s_hardware * hardware);

// DMI STUFF
#define CLI_DMI_BASE_BOARD "base_board"
#define CLI_DMI_BATTERY "battery"
#define CLI_DMI_BIOS "bios"
#define CLI_DMI_CHASSIS "chassis"
#define CLI_DMI_MEMORY "memory"
#define CLI_DMI_MEMORY_BANK "bank"
#define CLI_DMI_PROCESSOR "cpu"
#define CLI_DMI_SYSTEM "system"
#define CLI_DMI_IPMI "ipmi"
#define CLI_DMI_CACHE "cache"
#define CLI_DMI_OEM "oem"
#define CLI_DMI_SECURITY "security"
#define CLI_DMI_LIST CLI_SHOW_LIST
void main_show_dmi(int argc, char **argv, struct s_hardware *hardware);
void show_dmi_memory_modules(int argc, char **argv,
			     struct s_hardware *hardware);
void show_dmi_memory_bank(int argc, char **argv, struct s_hardware *hardware);

// PCI STUFF
#define CLI_PCI_DEVICE "device"
void main_show_pci(int argc, char **argv, struct s_hardware *hardware);

// CPU STUFF
void main_show_cpu(int argc, char **argv, struct s_hardware *hardware);

// DISK STUFF
void disks_summary(int argc, char **argv, struct s_hardware *hardware);

// PXE STUFF
void main_show_pxe(int argc, char **argv, struct s_hardware *hardware);

// KERNEL STUFF
void main_show_kernel(int argc, char **argv, struct s_hardware *hardware);

// SYSLINUX STUFF
void main_show_syslinux(int argc, char **argv, struct s_hardware *hardware);

// VESA STUFF
void main_show_vesa(int argc, char **argv, struct s_hardware *hardware);

// VPD STUFF
void main_show_vpd(int argc __unused, char **argv __unused,
		   struct s_hardware *hardware);

// ACPI STUFF
void main_show_acpi(int argc __unused, char **argv __unused,
		                    struct s_hardware *hardware);

#endif
