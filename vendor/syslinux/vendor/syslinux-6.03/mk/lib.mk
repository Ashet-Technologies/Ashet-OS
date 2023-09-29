# -*- makefile -*-

include $(MAKEDIR)/syslinux.mk

# Support IA32 and x86_64 platforms with one build
# Set up architecture specifics; for cross compilation, set ARCH as apt
GCCOPT := $(call gcc_ok,-std=gnu99,)
ifeq ($(ARCH),i386)
	GCCOPT += $(call gcc_ok,-m32,)
	GCCOPT += $(call gcc_ok,-mpreferred-stack-boundary=2,)
	MARCH = i386
endif
ifeq ($(ARCH),x86_64)
	GCCOPT += $(call gcc_ok,-m64,)
	#let preferred-stack-boundary be default(=4)
	MARCH = x86-64
endif
GCCOPT += $(call gcc_ok,-fno-stack-protector,)
GCCOPT += $(call gcc_ok,-fwrapv,)
GCCOPT += $(call gcc_ok,-freg-struct-return,)
# Note -fPIE does not work with ld on x86_64, try -fPIC instead
# Does BIOS build require -fPIE?
GCCOPT += $(call gcc_ok,-fPIC)
GCCOPT += $(call gcc_ok,-fno-exceptions,)
GCCOPT += $(call gcc_ok,-fno-asynchronous-unwind-tables,)
GCCOPT += $(call gcc_ok,-fno-strict-aliasing,)
GCCOPT += $(call gcc_ok,-falign-functions=0,-malign-functions=0)
GCCOPT += $(call gcc_ok,-falign-jumps=0,-malign-jumps=0)
GCCOPT += $(call gcc_ok,-falign-labels=0,-malign-labels=0)
GCCOPT += $(call gcc_ok,-falign-loops=0,-malign-loops=0)

INCLUDE	= -I$(SRC)
STRIP	= strip --strip-all -R .comment -R .note

# zlib and libpng configuration flags
LIBFLAGS = -DDYNAMIC_CRC_TABLE -DPNG_NO_CONSOLE_IO \
	   -DPNG_NO_WRITE_SUPPORTED \
	   -DPNG_NO_MNG_FEATURES \
	   -DPNG_NO_READ_tIME -DPNG_NO_WRITE_tIME

# We need some features in libpng which apparently aren't available in the
# fixed-point versions.  It's OK, because we have to have a non-graphical
# fallback anyway, just use that on old machines...
# LIBFLAGS += -DPNG_NO_FLOATING_POINT_SUPPORTED

REQFLAGS  = $(GCCOPT) -g -D__COM32__ -D__FIRMWARE_$(FIRMWARE)__ \
	    -nostdinc -iwithprefix include -I. -I$(SRC)/sys \
	    -I$(SRC)/../include -I$(com32)/include/sys \
	    -I$(topdir)/core/include -I$(com32)/lib/ \
	    -I$(com32)/lib/sys/module -I$(OBJ)/../..
OPTFLAGS  = -Os -march=$(MARCH) -falign-functions=0 -falign-jumps=0 \
	    -falign-labels=0 -ffast-math -fomit-frame-pointer
WARNFLAGS = $(GCCWARN) -Wpointer-arith -Wwrite-strings -Wstrict-prototypes -Winline

CFLAGS  = $(OPTFLAGS) $(REQFLAGS) $(WARNFLAGS) $(LIBFLAGS)

ifndef EFI_BUILD
CFLAGS += -mregparm=3 -DREGPARM=3
endif

VPATH = $(SRC)
LIBOTHER_OBJS = \
	atoi.o atol.o atoll.o calloc.o creat.o		\
	fgets.o fprintf.o fputc.o	\
	putchar.o				\
	getopt.o getopt_long.o						\
	lrand48.o stack.o memccpy.o memchr.o 		\
	mempcpy.o memmem.o memmove.o memswap.o	\
	perror.o qsort.o seed48.o \
	srand48.o sscanf.o 						\
	strerror.o errlist.o		\
	strnlen.o							\
	strncat.o strndup.o		\
	stpncpy.o						\
	strntoimax.o strsep.o strspn.o strstr.o				\
	strtoimax.o strtok.o strtol.o strtoll.o strtoull.o		\
	strtoumax.o vprintf.o vsprintf.o		\
	asprintf.o vasprintf.o			\
	vsscanf.o							\
	skipspace.o							\
	chrreplace.o							\
	bufprintf.o							\
	inet.o dhcppack.o dhcpunpack.o					\
	strreplace.o							\
	lstrdup.o						\
	\
	suffix_number.o							\
	\
	getcwd.o fdopendir.o	\
	\
	sys/line_input.o				\
	sys/colortable.o sys/screensize.o				\
	\
	sys/stdcon_read.o sys/stdcon_write.o sys/rawcon_read.o		\
	sys/rawcon_write.o		\
	sys/null_read.o sys/null_write.o sys/serial_write.o		\
	\
	sys/xserial_write.o						\
	\
	sys/ansi.o							\
	\
	sys/ansicon_write.o sys/ansiserial_write.o			\
	\
	pci/cfgtype.o pci/scan.o pci/bios.o					\
	pci/readb.o pci/readw.o pci/readl.o			\
	pci/writeb.o pci/writew.o pci/writel.o	\
	\
	sys/x86_init_fpu.o math/pow.o math/strtod.o			\
	syslinux/disk.o							\
	\
	syslinux/setup_data.o

## CORE OBJECTS, INCLUDED IN THE ROOT COM32 MODULE
LIBENTRY_OBJS = \
	sys/intcall.o sys/farcall.o sys/cfarcall.o sys/zeroregs.o	\
	sys/argv.o sys/sleep.o						\
	sys/fileinfo.o sys/opendev.o sys/read.o sys/write.o sys/ftell.o \
	sys/close.o sys/open.o sys/fileread.o sys/fileclose.o		\
	sys/openmem.o					\
	sys/isatty.o sys/fstat.o					\
	\
	dprintf.o vdprintf.o						\
	\
	syslinux/idle.o							\
	\
	exit.o

LIBGCC_OBJS = \
	libgcc/__ashldi3.o libgcc/__udivdi3.o			\
	libgcc/__negdi2.o libgcc/__ashrdi3.o libgcc/__lshrdi3.o		\
	libgcc/__muldi3.o libgcc/__udivmoddi4.o libgcc/__umoddi3.o	\
	libgcc/__divdi3.o libgcc/__moddi3.o

LIBCONSOLE_OBJS = \
	\
	sys/openconsole.o sys/line_input.o				\
	sys/colortable.o sys/screensize.o				\
	\
	sys/stdcon_read.o sys/rawcon_read.o		\
	sys/rawcon_write.o						\
	sys/null_write.o sys/serial_write.o		\
	\
	sys/xserial_write.o						\
	\
	sys/ansi.o							\
	\
	sys/ansicon_write.o sys/ansiserial_write.o	\
	\
	syslinux/serial.o

LIBLOAD_OBJS = \
	syslinux/addlist.o syslinux/freelist.o syslinux/memmap.o	\
	syslinux/movebits.o syslinux/shuffle.o syslinux/shuffle_pm.o	\
	syslinux/shuffle_rm.o syslinux/biosboot.o syslinux/zonelist.o	\
	syslinux/dump_mmap.o syslinux/dump_movelist.o			\
	\
	syslinux/run_default.o syslinux/run_command.o			\
	syslinux/cleanup.o syslinux/localboot.o	syslinux/runimage.o	\
	\
	syslinux/loadfile.o syslinux/floadfile.o syslinux/zloadfile.o	\
	\
	syslinux/load_linux.o syslinux/initramfs.o			\
	syslinux/initramfs_file.o syslinux/initramfs_loadfile.o		\
	syslinux/initramfs_archive.o

LIBMODULE_OBJS = \
	sys/module/common.o sys/module/$(ARCH)/elf_module.o		\
	sys/module/elfutils.o	\
	sys/module/exec.o sys/module/elf_module.o

# ZIP library object files
LIBZLIB_OBJS = \
	zlib/adler32.o zlib/compress.o zlib/crc32.o 			\
	zlib/uncompr.o zlib/deflate.o zlib/trees.o zlib/zutil.o		\
	zlib/inflate.o zlib/infback.o zlib/inftrees.o zlib/inffast.o	\
	sys/zfile.o sys/zfopen.o

MINLIBOBJS = \
	$(addprefix $(OBJ)/,syslinux/ipappend.o \
	syslinux/dsinfo.o \
	$(LIBOTHER_OBJS) \
	$(LIBGCC_OBJS) \
	$(LIBCONSOLE_OBJS) \
	$(LIBLOAD_OBJS) \
	$(LIBZLIB_OBJS))
#	$(LIBVESA_OBJS)

CORELIBOBJS = \
	memcpy.o memset.o memcmp.o printf.o strncmp.o vfprintf.o 	\
	strlen.o vsnprintf.o snprintf.o stpcpy.o strcmp.o strdup.o 	\
	strcpy.o strncpy.o setjmp.o fopen.o fread.o fread2.o puts.o 	\
	strtoul.o strntoumax.o strcasecmp.o 				\
	sprintf.o strlcat.o strchr.o strlcpy.o strncasecmp.o ctypes.o 	\
	fputs.o fwrite2.o fwrite.o fgetc.o fclose.o lmalloc.o 		\
	sys/err_read.o sys/err_write.o sys/null_read.o 			\
	sys/stdcon_write.o						\
	syslinux/memscan.o strrchr.o strcat.o				\
	libgcc/__ashldi3.o libgcc/__udivdi3.o				\
	libgcc/__negdi2.o libgcc/__ashrdi3.o libgcc/__lshrdi3.o		\
	libgcc/__muldi3.o libgcc/__udivmoddi4.o libgcc/__umoddi3.o	\
	libgcc/__divdi3.o libgcc/__moddi3.o				\
	syslinux/debug.o						\
	$(LIBENTRY_OBJS) \
	$(LIBMODULE_OBJS)

LDFLAGS	= -m elf_$(ARCH) --hash-style=gnu -T $(com32)/lib/$(ARCH)/elf.ld

.SUFFIXES: .c .o .a .so .lo .i .S .s .ls .ss .lss

% : %.c # Cancel default rule

% : %.S

%.o: %.c
	$(CC) $(MAKEDEPS) $(CFLAGS) -c -o $@ $<

.c.i:
	$(CC) $(MAKEDEPS) $(CFLAGS) -E -o $@ $<

%.s: %.c
	$(CC) $(MAKEDEPS) $(CFLAGS) -S -o $@ $<

%.o: %.S
	$(CC) $(MAKEDEPS) $(CFLAGS) -D__ASSEMBLY__ -c -o $@ $<

.S.s:
	$(CC) $(MAKEDEPS) $(CFLAGS) -D__ASSEMBLY__ -E -o $@ $<

.S.lo:
	$(CC) $(MAKEDEPS) $(CFLAGS) $(SOFLAGS) -D__ASSEMBLY__ -c -o $@ $<

.S.ls:
	$(CC) $(MAKEDEPS) $(CFLAGS) $(SOFLAGS) -D__ASSEMBLY__ -E -o $@ $<

%(OBJ)/%.o: $(SRC)/%.s
	$(CC) $(MAKEDEPS) $(CFLAGS) -x assembler -c -o $@ $<

.ls.lo:
	$(CC) $(MAKEDEPS) $(CFLAGS) $(SOFLAGS) -x assembler -c -o $@ $<

.c.lo:
	$(CC) $(MAKEDEPS) $(CFLAGS) $(SOFLAGS) -c -o $@ $<

.c.ls:
	$(CC) $(MAKEDEPS) $(CFLAGS) $(SOFLAGS) -S -o $@ $<

%.c32: %.elf
	$(OBJCOPY) --strip-debug --strip-unneeded $< $@
