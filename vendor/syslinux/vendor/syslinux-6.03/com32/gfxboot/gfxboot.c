/*
 *
 * gfxboot.c
 *
 * A com32 module to load gfxboot graphics.
 *
 * Copyright (c) 2009 Steffen Winterfeldt.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, Inc., 53 Temple Place Ste 330, Boston MA
 * 02111-1307, USA; either version 2 of the License, or (at your option) any
 * later version; incorporated herein by reference.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <minmax.h>
#include <ctype.h>

#include <syslinux/loadfile.h>
#include <syslinux/config.h>
#include <syslinux/linux.h>
#include <syslinux/boot.h>
#include <console.h>
#include <com32.h>


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#define MAX_CONFIG_LINE_LEN	2048
#define MAX_CMDLINE_LEN		2048

// buffer for realmode callback
// must be at least block size; can in theory be larger than 4k, but there's
// not enough space left
#define REALMODE_BUF_SIZE	4096
#define LOWMEM_BUF_SIZE		65536

// gfxboot working memory in MB
#define	GFX_MEMORY_SIZE		7

// read chunk size for progress bar
#define CHUNK_SIZE	(64 << 10)

// callback function numbers
#define GFX_CB_INIT		0
#define GFX_CB_DONE		1
#define GFX_CB_INPUT		2
#define GFX_CB_MENU_INIT	3
#define GFX_CB_INFOBOX_INIT	4
#define GFX_CB_INFOBOX_DONE	5
#define GFX_CB_PROGRESS_INIT	6
#define GFX_CB_PROGRESS_DONE	7
#define GFX_CB_PROGRESS_UPDATE	8
#define GFX_CB_PROGRESS_LIMIT	9		// unused
#define GFX_CB_PASSWORD_INIT	10
#define GFX_CB_PASSWORD_DONE	11

// real mode code chunk, will be placed into lowmem buffer
extern const char realmode_callback_start[], realmode_callback_end[];

// gets in the way
#undef linux


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// gfxboot config data (64 bytes)
typedef struct __attribute__ ((packed)) {
  uint8_t bootloader;		//  0: boot loader type (0: lilo, 1: syslinux, 2: grub)
  uint8_t sector_shift;		//  1: sector shift
  uint8_t media_type;		//  2: media type (0: disk, 1: floppy, 2: cdrom)
  uint8_t failsafe;		//  3: turn on failsafe mode (bitmask)
				//    0: SHIFT pressed
				//    1: skip gfxboot
				//    2: skip monitor detection
  uint8_t sysconfig_size;	//  4: size of sysconfig data
  uint8_t boot_drive;		//  5: BIOS boot drive
  uint16_t callback;		//  6: offset to callback handler
  uint16_t bootloader_seg;	//  8: code/data segment used by bootloader; must follow gfx_callback
  uint16_t serial_port;		// 10: syslinux initialized serial port from 'serial' option
  uint32_t user_info_0;		// 12: data for info box
  uint32_t user_info_1;		// 16: data for info box
  uint32_t bios_mem_size;	// 20: BIOS memory size (in bytes)
  uint16_t xmem_0;		// 24: extended mem area 0 (start:size in MB; 12:4 bits) - obsolete
  uint16_t xmem_1;		// 26: extended mem area 1 - obsolete
  uint16_t xmem_2;		// 28: extended mem area 2 - obsolete
  uint16_t xmem_3;		// 30: extended mem area 3 - obsolete
  uint32_t file;		// 32: start of gfx file
  uint32_t archive_start;	// 36: start of cpio archive
  uint32_t archive_end;		// 40: end of cpio archive
  uint32_t mem0_start;		// 44: low free memory start
  uint32_t mem0_end;		// 48: low free memory end
  uint32_t xmem_start;		// 52: extended mem start
  uint32_t xmem_end;		// 56: extended mem end
  uint16_t features;		// 60: feature flags returned by GFX_CB_INIT
  				//    0: GFX_CB_MENU_INIT accepts 32 bit addresses
  				//    1: knows about xmem_start, xmem_end
  uint16_t reserved_1;		// 62:
  uint32_t gfxboot_cwd;		// 64: if set, points to current gfxboot working directory relative
				//     to syslinux working directory
} gfx_config_t;


// gfxboot menu description (18 bytes)
typedef struct __attribute__ ((packed)) {
  uint16_t entries;
  char *default_entry;
  char *label_list;
  uint16_t label_size;
  char *arg_list;
  uint16_t arg_size;
} gfx_menu_t;


// menu description
typedef struct menu_s {
  struct menu_s *next;
  char *label;		// config entry name
  char *menu_label;	// text to show in boot menu
  char *kernel;		// name of program to load
  char *alt_kernel;	// alternative name in case user has replaced it
  char *linux;		// de facto an alias for 'kernel'
  char *localboot;	// boot from local disk
  char *initrd;		// initrd as separate line (instead of as part of 'append')
  char *append;		// kernel args
  char *ipappend;	// append special pxelinux args (see doc)
} menu_t;


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
gfx_config_t gfx_config;
gfx_menu_t gfx_menu;

menu_t *menu;
menu_t *menu_default;
static menu_t *menu_ptr, **menu_next;

struct {
  uint32_t jmp_table[12];
  uint16_t code_seg;
  char fname_buf[64];
} gfx;

void *lowmem_buf;

int timeout;

char cmdline[MAX_CMDLINE_LEN];

// progress bar is visible
unsigned progress_active;


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
void show_message(char *file);
char *get_config_file_name(void);
char *skip_nonspaces(char *s);
void chop_line(char *s);
int read_config_file(const char *filename);
unsigned magic_ok(unsigned char *buf, unsigned *code_size);
unsigned find_file(unsigned char *buf, unsigned len, unsigned *gfx_file_start, unsigned *file_len, unsigned *code_size);
int gfx_init(char *file);
int gfx_menu_init(void);
void gfx_done(void);
int gfx_input(void);
void gfx_infobox(int type, char *str1, char *str2);
void gfx_progress_init(ssize_t kernel_size, char *label);
void gfx_progress_update(ssize_t size);
void gfx_progress_done(void);
void *load_one(char *file, ssize_t *file_size);
void boot(int index);
void boot_entry(menu_t *menu_ptr, char *arg);


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
int main(int argc, char **argv)
{
  int menu_index;
  const union syslinux_derivative_info *sdi;
  char working_dir[256];

  openconsole(&dev_stdcon_r, &dev_stdcon_w);

  lowmem_buf = lmalloc(LOWMEM_BUF_SIZE);
  if (!lowmem_buf) {
    printf("Could not allocate memory.\n");
    return 1;
  }

  sdi = syslinux_derivative_info();

  gfx_config.sector_shift = sdi->disk.sector_shift;
  gfx_config.boot_drive = sdi->disk.drive_number;

  if(sdi->c.filesystem == SYSLINUX_FS_PXELINUX) {
    gfx_config.sector_shift = 11;
    gfx_config.boot_drive = 0;
  }

  gfx_config.media_type = gfx_config.boot_drive < 0x80 ? 1 : 0;

  if(sdi->c.filesystem == SYSLINUX_FS_ISOLINUX) {
    gfx_config.media_type = sdi->iso.cd_mode ? 0 : 2;
  }

  gfx_config.bootloader = 1;
  gfx_config.sysconfig_size = sizeof gfx_config;
  gfx_config.bootloader_seg = 0;	// apparently not needed

  if(argc < 2) {
    printf("Usage: gfxboot.c32 bootlogo_file [message_file]\n");
    if(argc > 2) show_message(argv[2]);

    return 0;
  }

  if(read_config_file("~")) {
    printf("Error reading config file\n");
    if(argc > 2) show_message(argv[2]);

    return 0;
  }

  if(getcwd(working_dir, sizeof working_dir)) {
    gfx_config.gfxboot_cwd = (uint32_t) working_dir;
  }

  if(gfx_init(argv[1])) {
    printf("Error setting up gfxboot\n");
    if(argc > 2) show_message(argv[2]);

    return 0;
  }

  gfx_menu_init();

  for(;;) {
    menu_index = gfx_input();

    // abort gfx, return to text mode prompt
    if(menu_index == -1) {
      gfx_done();
      break;
    }

    // does not return if it succeeds
    boot(menu_index);
  }

  if(argc > 2) show_message(argv[2]);

  return 0;
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
void show_message(char *file)
{
  int c;
  FILE *f;

  if(!(f = fopen(file, "r"))) return;

  while((c = getc(f)) != EOF) {
    if(c < ' ' && c != '\n' && c != '\t') continue;
    printf("%c", c);
  }

  fclose(f);
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
char *skip_nonspaces(char *s)
{
  while(*s && *s != ' ' && *s != '\t') s++;

  return s;
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
void chop_line(char *s)
{
  int i = strlen(s);

  if(!i) return;

  while(--i >= 0) {
    if(s[i] == ' ' || s[i] == '\t' || s[i] == '\n') {
      s[i] = 0;
    }
    else {
      break;
    }
  }
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Read and parse syslinux config file.
//
// return:
//   0: ok, 1: error
//
int read_config_file(const char *filename)
{
  FILE *f;
  char *s, *t, buf[MAX_CONFIG_LINE_LEN];
  unsigned u, top_level = 0, text = 0;

  if(!strcmp(filename, "~")) {
    top_level = 1;
    filename = syslinux_config_file();
    gfx_menu.entries = 0;
    gfx_menu.label_size = 0;
    gfx_menu.arg_size = 0;
    menu_ptr = NULL;
    menu_next = &menu;
    menu_default = calloc(1, sizeof *menu_default);
  }

  if(!(f = fopen(filename, "r"))) return 1;

  while((s = fgets(buf, sizeof buf, f))) {
    chop_line(s);
    s = skipspace(s);
    if(!*s || *s == '#') continue;
    t = skip_nonspaces(s);
    if(*t) *t++ = 0;
    t = skipspace(t);

    if(!strcasecmp(s, "endtext")) {
      text = 0;
      continue;
    }

    if (text)
      continue;

    if(!strcasecmp(s, "timeout")) {
      timeout = atoi(t);
      continue;
    }

    if(!strcasecmp(s, "default")) {
      menu_default->label = strdup(t);
      u = strlen(t);
      if(u > gfx_menu.label_size) gfx_menu.label_size = u;
      continue;
    }

    if(!strcasecmp(s, "label")) {
      menu_ptr = *menu_next = calloc(1, sizeof **menu_next);
      menu_next = &menu_ptr->next;
      gfx_menu.entries++;
      menu_ptr->label = menu_ptr->menu_label = strdup(t);
      u = strlen(t);
      if(u > gfx_menu.label_size) gfx_menu.label_size = u;
      continue;
    }

    if(!strcasecmp(s, "kernel") && menu_ptr) {
      menu_ptr->kernel = strdup(t);
      continue;
    }

    if(!strcasecmp(s, "linux") && menu_ptr) {
      menu_ptr->linux = strdup(t);
      continue;
    }

    if(!strcasecmp(s, "localboot") && menu_ptr) {
      menu_ptr->localboot = strdup(t);
      continue;
    }

    if(!strcasecmp(s, "initrd") && menu_ptr) {
      menu_ptr->initrd = strdup(t);
      continue;
    }

    if(!strcasecmp(s, "append")) {
      (menu_ptr ?: menu_default)->append = strdup(t);
      u = strlen(t);
      if(u > gfx_menu.arg_size) gfx_menu.arg_size = u;
      continue;
    }

    if(!strcasecmp(s, "ipappend") || !strcasecmp(s, "sysappend")) {
      (menu_ptr ?: menu_default)->ipappend = strdup(t);
      continue;
    }

    if(!strcasecmp(s, "text")) {
      text = 1;
      continue;
    }

    if(!strcasecmp(s, "menu") && menu_ptr) {
      s = skipspace(t);
      t = skip_nonspaces(s);
      if(*t) *t++ = 0;
      t = skipspace(t);

      if(!strcasecmp(s, "label")) {
        menu_ptr->menu_label = strdup(t);
        u = strlen(t);
        if(u > gfx_menu.label_size) gfx_menu.label_size = u;
        continue;
      }

      if(!strcasecmp(s, "include")) {
        goto do_include;
      }
    }

    if (!strcasecmp(s, "include")) {
do_include:
      s = t;
      t = skip_nonspaces(s);
      if (*t) *t = 0;
      read_config_file(s);
    }
  }

  fclose(f);

  if (!top_level)
    return 0;

  if (gfx_menu.entries == 0) {
    printf("No LABEL keywords found.\n");
    return 1;
  }

  // final '\0'
  gfx_menu.label_size++;
  gfx_menu.arg_size++;

  // ensure we have a default entry
  if(!menu_default->label) menu_default->label = menu->label;

  if(menu_default->label) {
    for(menu_ptr = menu; menu_ptr; menu_ptr = menu_ptr->next) {
      if(!strcmp(menu_default->label, menu_ptr->label)) {
        menu_default->menu_label = menu_ptr->menu_label;
        break;
      }
    }
  }

  gfx_menu.default_entry = menu_default->menu_label;
  gfx_menu.label_list = calloc(gfx_menu.entries, gfx_menu.label_size);
  gfx_menu.arg_list = calloc(gfx_menu.entries, gfx_menu.arg_size);

  for(u = 0, menu_ptr = menu; menu_ptr; menu_ptr = menu_ptr->next, u++) {
    if(!menu_ptr->append) menu_ptr->append = menu_default->append;
    if(!menu_ptr->ipappend) menu_ptr->ipappend = menu_default->ipappend;

    if(menu_ptr->menu_label) strcpy(gfx_menu.label_list + u * gfx_menu.label_size, menu_ptr->menu_label);
    if(menu_ptr->append) strcpy(gfx_menu.arg_list + u * gfx_menu.arg_size, menu_ptr->append);
  }

  return 0;
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Check header and return code start offset.
//
unsigned magic_ok(unsigned char *buf, unsigned *code_size)
{
  if(
    *(unsigned *) buf == 0x0b2d97f00 &&		// magic id
    (buf[4] == 8)				// version 8
  ) {
    *code_size = *(unsigned *) (buf + 12);
    return *(unsigned *) (buf + 8);
  }

  return 0;
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Search (cpio archive) for gfx file.
//
unsigned find_file(unsigned char *buf, unsigned len, unsigned *gfx_file_start, unsigned *file_len, unsigned *code_size)
{
  unsigned i, fname_len, code_start = 0;

  *gfx_file_start = 0;
  *code_size = 0;

  if((code_start = magic_ok(buf, code_size))) return code_start;

  for(i = 0; i < len;) {
    if((len - i) >= 0x1a && (buf[i] + (buf[i + 1] << 8)) == 0x71c7) {
      fname_len = *(unsigned short *) (buf + i + 20);
      *file_len = *(unsigned short *) (buf + i + 24) + (*(unsigned short *) (buf + i + 22) << 16);
      i += 26 + fname_len;
      i = ((i + 1) & ~1);
      if((code_start = magic_ok(buf + i, code_size))) {
        *gfx_file_start = i;
        return code_start;
      }
      i += *file_len;
      i = ((i + 1) & ~1);
    }
    else {
      break;
    }
  }

  return code_start;
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Initialize gfxboot code.
//
// return:
//   0: ok, 1: error
//
int gfx_init(char *file)
{
  size_t archive_size = 0;
  void *archive;
  unsigned code_start, code_size, file_start, file_len, u;
  com32sys_t r;
  void *lowmem = lowmem_buf;
  unsigned lowmem_size = LOWMEM_BUF_SIZE;

  memset(&r,0,sizeof(r));
  progress_active = 0;

  printf("Loading %s...\n", file);
  if(loadfile(file, &archive, &archive_size)) return 1;

  if(!archive_size) return 1;

  // printf("%s: %d\n", file, archive_size);

  gfx_config.archive_start = (uint32_t) archive;
  gfx_config.archive_end = gfx_config.archive_start + archive_size;

  // locate file inside cpio archive
  if(!(code_start = find_file(archive, archive_size, &file_start, &file_len, &code_size))) {
    printf("%s: invalid file format\n", file);
    return 1;
  }

#if 0
  printf(
    "code_start = 0x%x, code_size = 0x%x\n"
    "archive_start = 0x%x, archive size = 0x%x\n"
    "file_start = 0x%x, file_len = 0x%x\n",
    code_start, code_size,
    gfx_config.archive_start, archive_size,
    file_start, file_len
  );
#endif

  gfx_config.file = gfx_config.archive_start + file_start;

  u = realmode_callback_end - realmode_callback_start;
  u = (u + REALMODE_BUF_SIZE + 0xf) & ~0xf;

  if(u + code_size > lowmem_size) {
    printf("lowmem buffer too small: size %u, needed %u\n", lowmem_size, u + code_size);
    return 1;
  }

  memcpy(lowmem + REALMODE_BUF_SIZE, realmode_callback_start,
	 realmode_callback_end - realmode_callback_start);

  // fill in buffer size and location
  *(uint16_t *) (lowmem + REALMODE_BUF_SIZE) = REALMODE_BUF_SIZE;
  *(uint16_t *) (lowmem + REALMODE_BUF_SIZE + 2) = (uint32_t) lowmem >> 4;

  gfx_config.bootloader_seg = ((uint32_t) lowmem + REALMODE_BUF_SIZE) >> 4;
  gfx_config.callback = 4;	// start address

  lowmem += u;
  lowmem_size -= u;

  memcpy(lowmem, archive + file_start + code_start, code_size);

  gfx_config.mem0_start = (uint32_t) lowmem + code_size;
  gfx_config.mem0_end = (uint32_t) lowmem + lowmem_size;
  // align a bit
  gfx_config.mem0_start = (gfx_config.mem0_start + 0xf) & ~0xf;

  gfx_config.xmem_start = (uint32_t) malloc(GFX_MEMORY_SIZE << 20);
  if(gfx_config.xmem_start) {
    gfx_config.xmem_end = gfx_config.xmem_start + (GFX_MEMORY_SIZE << 20);
  }

  // fake; not used anyway
  gfx_config.bios_mem_size = 256 << 20;

  gfx.code_seg = (uint32_t) lowmem >> 4;

  for(u = 0; u < sizeof gfx.jmp_table / sizeof *gfx.jmp_table; u++) {
    gfx.jmp_table[u] = (gfx.code_seg << 16) + *(uint16_t *) (lowmem + 2 * u);
  }

#if 0
  for(u = 0; u < sizeof gfx.jmp_table / sizeof *gfx.jmp_table; u++) {
    printf("%d: 0x%08x\n", u, gfx.jmp_table[u]);
  }
#endif

  // we are ready to start

  r.esi.l = (uint32_t) &gfx_config;
  __farcall(gfx.code_seg, gfx.jmp_table[GFX_CB_INIT], &r, &r);

  if((r.eflags.l & EFLAGS_CF)) {
    printf("graphics initialization failed\n");

    return 1;
  }

  if((gfx_config.features & 3) != 3) {
    gfx_done();

    printf("%s: boot graphics code too old, please use newer version\n", file);

    return 1;
  }


  return 0;
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
int gfx_menu_init(void)
{
  com32sys_t r;

  memset(&r,0,sizeof(r));
  r.esi.l = (uint32_t) &gfx_menu;
  __farcall(gfx.code_seg, gfx.jmp_table[GFX_CB_MENU_INIT], &r, &r);

  return 0;
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
void gfx_done(void)
{
  com32sys_t r;

  memset(&r,0,sizeof(r));
  gfx_progress_done();

  __farcall(gfx.code_seg, gfx.jmp_table[GFX_CB_DONE], &r, &r);
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Run gfxboot main loop.
//
// return:
//   boot menu index (-1: go to text mode prompt)
//
int gfx_input(void)
{
  com32sys_t r;

  memset(&r,0,sizeof(r));
  r.edi.l = (uint32_t) cmdline;
  r.ecx.l = sizeof cmdline;
  r.eax.l = timeout * 182 / 100;
  timeout = 0;		// use timeout only first time
  __farcall(gfx.code_seg, gfx.jmp_table[GFX_CB_INPUT], &r, &r);
  if((r.eflags.l & EFLAGS_CF)) r.eax.l = 1;

  if(r.eax.l == 1) return -1;

  return r.ebx.l;
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
void gfx_infobox(int type, char *str1, char *str2)
{
  com32sys_t r;

  memset(&r,0,sizeof(r));
  r.eax.l = type;
  r.esi.l = (uint32_t) str1;
  r.edi.l = (uint32_t) str2;
  __farcall(gfx.code_seg, gfx.jmp_table[GFX_CB_INFOBOX_INIT], &r, &r);
  r.edi.l = r.eax.l = 0;
  __farcall(gfx.code_seg, gfx.jmp_table[GFX_CB_INPUT], &r, &r);
  __farcall(gfx.code_seg, gfx.jmp_table[GFX_CB_INFOBOX_DONE], &r, &r);
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
void gfx_progress_init(ssize_t kernel_size, char *label)
{
  com32sys_t r;

  memset(&r,0,sizeof(r));
  if(!progress_active) {
    r.eax.l = kernel_size >> gfx_config.sector_shift;		// in sectors
    r.esi.l = (uint32_t) label;
    __farcall(gfx.code_seg, gfx.jmp_table[GFX_CB_PROGRESS_INIT], &r, &r);
  }

  progress_active = 1;
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
void gfx_progress_update(ssize_t advance)
{
  com32sys_t r;

  memset(&r,0,sizeof(r));
  if(progress_active) {
    r.eax.l = advance >> gfx_config.sector_shift;		// in sectors
    __farcall(gfx.code_seg, gfx.jmp_table[GFX_CB_PROGRESS_UPDATE], &r, &r);
  }
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
void gfx_progress_done(void)
{
  com32sys_t r;

  memset(&r,0,sizeof(r));
  if(progress_active) {
    __farcall(gfx.code_seg, gfx.jmp_table[GFX_CB_PROGRESS_DONE], &r, &r);
  }

  progress_active = 0;
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Read file and update progress bar.
//
void *load_one(char *file, ssize_t *file_size)
{
  int fd;
  void *buf = NULL;
  char *str;
  struct stat sbuf;
  ssize_t size = 0, cur, i;

  *file_size = 0;

  if((fd = open(file, O_RDONLY)) == -1) {
    asprintf(&str, "%s: file not found", file);
    gfx_infobox(0, str, NULL);
    free(str);
    return buf;
  }

  if(!fstat(fd, &sbuf) && S_ISREG(sbuf.st_mode)) size = sbuf.st_size;

  i = 0;

  if(size) {
    buf = malloc(size);
    for(i = 1, cur = 0 ; cur < size && i > 0; cur += i) {
      i = read(fd, buf + cur, min(CHUNK_SIZE, size - cur));
      if(i == -1) break;
      gfx_progress_update(i);
    }
  }
  else {
    do {
      buf = realloc(buf, size + CHUNK_SIZE);
      i = read(fd, buf + size, CHUNK_SIZE);
      if(i == -1) break;
      size += i;
      gfx_progress_update(i);
    } while(i > 0);
  }

  close(fd);

  if(i == -1) {
    asprintf(&str, "%s: read error @ %d", file, size);
    gfx_infobox(0, str, NULL);
    free(str);
    free(buf);
    buf = NULL;
    size = 0;
  }

  *file_size = size;

  return buf;
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Boot menu entry.
//
// cmdline can optionally start with label string.
//
void boot(int index)
{
  char *arg, *alt_kernel;
  menu_t *menu_ptr;
  int i, label_len;
  unsigned ipapp;
  const struct syslinux_ipappend_strings *ipappend;
  char *gfxboot_cwd = (char *) gfx_config.gfxboot_cwd;

  if(gfxboot_cwd) {
    chdir(gfxboot_cwd);
    gfx_config.gfxboot_cwd = 0;
  }

  for(menu_ptr = menu; menu_ptr; menu_ptr = menu_ptr->next, index--) {
    if(!index) break;
  }

  // invalid index or menu entry
  if(!menu_ptr || !menu_ptr->menu_label) return;

  arg = skipspace(cmdline);
  label_len = strlen(menu_ptr->menu_label);

  // if it does not start with label string, assume first word is kernel name
  if(strncmp(arg, menu_ptr->menu_label, label_len)) {
    alt_kernel = arg;
    arg = skip_nonspaces(arg);
    if(*arg) *arg++ = 0;
    if(*alt_kernel) menu_ptr->alt_kernel = alt_kernel;
  }
  else {
    arg += label_len;
  }

  arg = skipspace(arg);

  // handle IPAPPEND
  if(menu_ptr->ipappend && (ipapp = atoi(menu_ptr->ipappend))) {
    ipappend = syslinux_ipappend_strings();
    for(i = 0; i < ipappend->count; i++) {
      if((ipapp & (1 << i)) && ipappend->ptr[i]) {
        sprintf(arg + strlen(arg), " %s", ipappend->ptr[i]);
      }
    }
  }

  boot_entry(menu_ptr, arg);

  gfx_progress_done();
}


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Load & run kernel.
//
// Returns only on error.
//
void boot_entry(menu_t *menu_ptr, char *arg)
{
  void *kernel, *initrd_buf;
  ssize_t kernel_size = 0, initrd_size = 0;
  struct initramfs *initrd = NULL;
  char *file, *cmd_buf;
  int fd;
  struct stat sbuf;
  char *s, *s0, *t, *initrd_arg;

  if(!menu_ptr) return;

  if(menu_ptr->localboot) {
    gfx_done();
    syslinux_local_boot(strtol(menu_ptr->localboot, NULL, 0));

    return;
  }

  file = menu_ptr->alt_kernel;
  if(!file) file = menu_ptr->kernel;
  if(!file) file = menu_ptr->linux;
  if(!file) {
    gfx_done();
    asprintf(&cmd_buf, "%s %s", menu_ptr->label, arg);
    syslinux_run_command(cmd_buf);
    return;
  }

  // first, load kernel

  kernel_size = 0;

  if((fd = open(file, O_RDONLY)) >= 0) {
    if(!fstat(fd, &sbuf) && S_ISREG(sbuf.st_mode)) kernel_size = sbuf.st_size;
    close(fd);
  }

  gfx_progress_init(kernel_size, file);

  kernel = load_one(file, &kernel_size);

  if(!kernel) {
    return;
  }

  if(kernel_size < 1024 || *(uint32_t *) (kernel + 0x202) != 0x53726448) {
    // not a linux kernel
    gfx_done();
    asprintf(&cmd_buf, "%s %s", menu_ptr->label, arg);
    syslinux_run_command(cmd_buf);
    return;
  }

  // printf("kernel = %p, size = %d\n", kernel, kernel_size);

  // parse cmdline for "initrd" option

  initrd_arg = menu_ptr->initrd;

  s = s0 = strdup(arg);

  while(*s && strncmp(s, "initrd=", sizeof "initrd=" - 1)) {
    s = skipspace(skip_nonspaces(s));
  }

  if(*s) {
    s += sizeof "initrd=" - 1;
    *skip_nonspaces(s) = 0;
    initrd_arg = s;
  }
  else if(initrd_arg) {
    free(s0);
    initrd_arg = s0 = strdup(initrd_arg);
  }

  if(initrd_arg) {
    initrd = initramfs_init();

    while((t = strsep(&initrd_arg, ","))) {
      initrd_buf = load_one(t, &initrd_size);

      if(!initrd_buf) {
        printf("%s: read error\n", t);
        free(s0);
        return;
      }

      initramfs_add_data(initrd, initrd_buf, initrd_size, initrd_size, 4);

      // printf("initrd = %p, size = %d\n", initrd_buf, initrd_size);
    }
  }

  free(s0);

  gfx_done();

  syslinux_boot_linux(kernel, kernel_size, initrd, NULL, arg);
}


