## -----------------------------------------------------------------------
##
##   Copyright 1998-2009 H. Peter Anvin - All Rights Reserved
##   Copyright 2009-2014 Intel Corporation; author: H. Peter Anvin
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
##   Boston MA 02111-1307, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

#
# Makefile for the SYSLINUX core
#

VPATH = $(SRC)

# No builtin rules
MAKEFLAGS += -r
MAKE      += -r

include $(MAKEDIR)/embedded.mk
-include $(objdir)/version.mk

OPTFLAGS =
INCLUDES = -I$(SRC)/include -I$(com32)/include -I$(com32)/include/sys -I$(com32)/lib \
	-I$(SRC)/lwip/src/include -I$(SRC)/lwip/src/include/ipv4 -I$(SRC)/fs/pxe

# This is very similar to cp437; technically it's for Norway and Denmark,
# but it's unlikely the characters that are different will be used in
# filenames by other users.
CODEPAGE = cp865

# The targets to build in this directory...
BTARGET  = kwdhash.gen \
	   ldlinux.bss ldlinux.sys ldlinux.bin \
	   isolinux.bin isolinux-debug.bin pxelinux.0 lpxelinux.0

# All primary source files for the main syslinux files
NASMSRC	 := $(wildcard $(SRC)/*.asm)
NASMHDR  := $(wildcard $(SRC)/*.inc)
CSRC	 := $(shell find $(SRC) -name '*.c' -print)
SSRC	 := $(shell find $(SRC) -name '*.S' -print)
CHDR	 := $(shell find $(SRC) -name '*.h' -print)
OTHERSRC := keywords
ALLSRC    = $(NASMSRC) $(NASMHDR) $(CSRC) $(SSRC) $(CHDR) $(OTHERSRC)

COBJ	 := $(subst $(SRC)/,,$(patsubst %.c,%.o,$(CSRC)))
SOBJ	 := $(subst $(SRC)/,,$(patsubst %.S,%.o,$(SSRC)))

# To make this compatible with the following $(filter-out), make sure
# we prefix everything with $(SRC)
CORE_PXE_CSRC = \
	$(addprefix $(SRC)/fs/pxe/, dhcp_option.c pxe.c tftp.c urlparse.c bios.c)

LPXELINUX_CSRC = $(CORE_PXE_CSRC) \
	$(shell find $(SRC)/lwip -name '*.c' -print) \
	$(addprefix $(SRC)/fs/pxe/, \
		core.c dnsresolv.c ftp.c ftp_readdir.c gpxeurl.c http.c \
		http_readdir.c idle.c isr.c tcp.c)

PXELINUX_CSRC = $(CORE_PXE_CSRC) \
	$(shell find $(SRC)/legacynet -name '*.c' -print)

LPXELINUX_OBJS = $(subst $(SRC)/,,$(LPXELINUX_CSRC:%.c=%.o))
PXELINUX_OBJS  = $(subst $(SRC)/,,$(PXELINUX_CSRC:%.c=%.o))

UNITTEST_CSRC = $(shell find $(SRC) -path '*/tests/*.c' -print)
UNITTEST_OBJS = $(subst $(SRC)/,,$(UNITTEST_CSRC:%.c=%.o))

# Don't include console and network stack specific objects or unit tests
FILTER_OBJS = %rawcon.o %plaincon.o %pxelinux-c.o %ldlinux-c.o \
	%isolinux-c.o %localboot.o %pxeboot.o \
	$(subst $(OBJ)/,,$(UNITTEST_OBJS)) \
	$(subst $(OBJ)/,,$(LPXELINUX_OBJS)) \
	$(subst $(OBJ)/,,$(PXELINUX_OBJS))

ifdef EFI_BUILD
# EFI is single-threaded, and doesn't use the LZO assembly decoder
FILTER_OBJS += $(subst $(SRC)/,, \
	$(patsubst %.S,%.o, $(wildcard $(SRC)/lzo/*.S)) \
	$(patsubst %.c,%.o, $(wildcard $(SRC)/thread/*.c)) \
	$(patsubst %.S,%.o, $(wildcard $(SRC)/thread/*.S)))
endif

COBJS	 = $(filter-out $(FILTER_OBJS),$(COBJ))
SOBJS	 = $(filter-out $(FILTER_OBJS),$(SOBJ))

ifdef EFI_BUILD
COBJS += $(subst $(SRC)/,,$(CORE_PXE_CSRC:%.c=%.o) fs/pxe/ftp.o fs/pxe/ftp_readdir.o \
	fs/pxe/http.o fs/pxe/http_readdir.o)
endif

LIB	 = libcom32.a
LIBS	 = $(LIB) --whole-archive $(objdir)/com32/lib/libcom32core.a
LIBDEP   = $(filter-out -% %start%,$(LIBS))
LIBOBJS	 = $(COBJS) $(SOBJS)

NASMDEBUG = -g -F dwarf
NASMOPT  += $(NASMDEBUG)

PREPCORE = $(OBJ)/../lzo/prepcore

CFLAGS += -D__SYSLINUX_CORE__ -D__FIRMWARE_$(FIRMWARE)__ \
	  -I$(objdir) -DLDLINUX=\"$(LDLINUX)\"

# The DATE is set on the make command line when building binaries for
# official release.  Otherwise, substitute a hex string that is pretty much
# guaranteed to be unique to be unique from build to build.
ifndef HEXDATE
HEXDATE := $(shell $(PERL) $(SRC)/../now.pl $(SRCS))
endif
ifndef DATE
DATE    := $(shell sh $(SRC)/../gen-id.sh $(VERSION) $(HEXDATE))
endif

# Set up the NASM and LD options for the architecture
NASM_ELF = "unknown"
LD_PIE = "unknown"
ifeq ($(ARCH),i386)
	NASM_ELF = elf
	LD_PIE = -pie
endif
ifeq ($(ARCH),x86_64)
	NASM_ELF = elf64
	#LD_PIE = --pic-executable
	LD_PIE = 
endif

ifdef EFI_BUILD
all: makeoutputdirs $(filter-out %bios.o,$(COBJS) $(SOBJS)) codepage.o
else
all: makeoutputdirs $(BTARGET)
endif

makeoutputdirs:
	@mkdir -p $(sort $(dir $(COBJ) $(SOBJ)))

kwdhash.gen: keywords genhash.pl
	$(PERL) $(SRC)/genhash.pl < $(SRC)/keywords > $(OBJ)/kwdhash.gen

.PRECIOUS: %.elf

%.raw: %.elf
	$(OBJCOPY) -O binary -S $< $(@:.bin=.raw)

# GNU make 3.82 gets confused by the first form
.PRECIOUS: $(OBJ)/%.raw

%.bin: %.raw $(PREPCORE)
	$(PREPCORE) $< $@

%.o: %.asm kwdhash.gen $(OBJ)/../version.gen
	$(NASM) -f $(NASM_ELF) $(NASMOPT) -DDATE_STR="'$(DATE)'" \
		-DHEXDATE="$(HEXDATE)" \
		-D$(ARCH) \
		-I$(SRC)/ \
		-l $(@:.o=.lsr) -o $@ -MP -MD $(dir $@).$(notdir $@).d $<

AUXLIBS = libisolinux.a libisolinux-debug.a libldlinux.a \
	libpxelinux.a liblpxelinux.a
LDSCRIPT = $(SRC)/$(ARCH)/syslinux.ld

%.elf: %.o $(LIBDEP) $(LDSCRIPT) $(AUXLIBS)
	$(LD) $(LDFLAGS) -Bsymbolic $(LD_PIE) -E --hash-style=gnu -T $(LDSCRIPT) -M -o $@ $< \
		--start-group $(LIBS) $(subst $(*F).elf,lib$(*F).a,$@) --end-group \
		> $(@:.elf=.map)
	$(OBJDUMP) -h $@ > $(@:.elf=.sec)
	$(PERL) $(SRC)/lstadjust.pl $(@:.elf=.lsr) $(@:.elf=.sec) $(@:.elf=.lst)

libisolinux.a: rawcon.o localboot.o isolinux-c.o
	rm -f $@
	$(AR) cq $@ $^
	$(RANLIB) $@

libisolinux-debug.a: libisolinux.a
	cp $^ $@

# Legacy network stack
libpxelinux.a: rawcon.o pxeboot.o pxelinux-c.o $(PXELINUX_OBJS)
	rm -f $@
	$(AR) cq $@ $^
	$(RANLIB) $@

# LwIP network stack
liblpxelinux.a: rawcon.o pxeboot.o pxelinux-c.o $(LPXELINUX_OBJS)
	rm -f $@
	$(AR) cq $@ $^
	$(RANLIB) $@

libldlinux.a: plaincon.o localboot.o ldlinux-c.o
	rm -f $@
	$(AR) cq $@ $^
	$(RANLIB) $@

$(LIB): $(LIBOBJS)
	rm -f $@
	$(AR) cq $@ $^
	$(RANLIB) $@

pxelinux.o: pxelinux.asm kwdhash.gen ../version.gen
	$(NASM) -f $(NASM_ELF) $(NASMOPT) -DDATE_STR="'$(DATE)'" \
		-DHEXDATE="$(HEXDATE)" \
		-D$(ARCH) \
		-I$(SRC)/ \
		-DIS_LPXELINUX=0 \
		-l $(@:.o=.lsr) -o $@ -MP -MD $(dir $@).$(notdir $@).d $<

pxelinux.0: pxelinux.bin
	cp -f $< $@

lpxelinux.o: pxelinux.asm kwdhash.gen ../version.gen
	$(NASM) -f $(NASM_ELF) $(NASMOPT) -DDATE_STR="'$(DATE)'" \
		-DHEXDATE="$(HEXDATE)" \
		-D$(ARCH) \
		-I$(SRC)/ \
		-DIS_LPXELINUX=1 \
		-l $(@:.o=.lsr) -o $@ -MP -MD $(dir $@).$(notdir $@).d $<

lpxelinux.0: lpxelinux.bin
	cp -f $< $@

ldlinux.bss: ldlinux.bin
	dd if=$< of=$@ bs=512 count=1

ldlinux.sys: ldlinux.bin
	dd if=$< of=$@ bs=512 skip=2

codepage.cp: $(OBJ)/../codepage/$(CODEPAGE).cp
	cp -f $< $@

codepage.o: codepage.S codepage.cp

install: installer

install-lib: installer

install-all: install install-lib

netinstall: installer

tidy dist:
	find . -type f \( -name '*.o' -o -name '*.a' -o -name '.*.d' \
		-o -name '*.lst' \) -print | xargs -rt rm -f
	rm -f codepage.cp *.elf stupid.* patch.offset .depend
	rm -f *.elf.tmp *.sym
	rm -f *.lsr *.map *.sec *.raw
	rm -f $(OBSOLETE) $(LIB)

clean: tidy

spotless: clean
	rm -f $(BTARGET) *.bin *_bin.c

# Include dependencies file
-include $(shell find . -name '.*.d' -print)
