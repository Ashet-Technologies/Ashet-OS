## -*- makefile -*- -------------------------------------------------------
##   
##   Copyright 2008 H. Peter Anvin - All Rights Reserved
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
##   Boston MA 02110-1301, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

##
## ELF common configurables
##

include $(MAKEDIR)/syslinux.mk

# Support IA32 and x86_64 platforms with one build
# Set up architecture specifics; for cross compilation, set ARCH as apt
GCCOPT := $(call gcc_ok,-std=gnu99,)
ifeq ($(ARCH),i386)
	GCCOPT += $(call gcc_ok,-m32,)
	GCCOPT += $(call gcc_ok,-march=i386)
	GCCOPT += $(call gcc_ok,-mpreferred-stack-boundary=2,)
endif
ifeq ($(ARCH),x86_64)
	GCCOPT += $(call gcc_ok,-m64,)
	GCCOPT += $(call gcc_ok,-march=x86-64)
	#let preferred-stack-boundary be default (=4)
endif
GCCOPT += -Os -fomit-frame-pointer
GCCOPT += $(call gcc_ok,-fno-stack-protector,)
GCCOPT += $(call gcc_ok,-fwrapv,)
GCCOPT += $(call gcc_ok,-freg-struct-return,)
GCCOPT += $(call gcc_ok,-fno-exceptions,)
GCCOPT += $(call gcc_ok,-fno-asynchronous-unwind-tables,)
# Note -fPIE does not work with ld on x86_64, try -fPIC instead
# Does BIOS build depend on -fPIE?
GCCOPT += $(call gcc_ok,-fPIC)
GCCOPT += $(call gcc_ok,-falign-functions=0,-malign-functions=0)
GCCOPT += $(call gcc_ok,-falign-jumps=0,-malign-jumps=0)
GCCOPT += $(call gcc_ok,-falign-labels=0,-malign-labels=0)
GCCOPT += $(call gcc_ok,-falign-loops=0,-malign-loops=0)

com32 = $(topdir)/com32
core = $(topdir)/core

ifneq ($(NOGPL),1)
GPLLIB     = $(objdir)/com32/gpllib/libgpl.c32
GPLINCLUDE = -I$(com32)/gplinclude
else
GPLLIB     =
GPLINCLUDE =
endif

CFLAGS     = $(GCCOPT) $(GCCWARN) -W -Wall \
	     -fomit-frame-pointer -D__COM32__ -D__FIRMWARE_$(FIRMWARE)__ -DDYNAMIC_MODULE \
	     -nostdinc -iwithprefix include \
	     -I$(com32)/libutil/include -I$(com32)/include \
		-I$(com32)/include/sys $(GPLINCLUDE) -I$(core)/include \
		-I$(objdir) -DLDLINUX=\"$(LDLINUX)\"
ifndef EFI_BUILD
CFLAGS	  += -mregparm=3 -DREGPARM=3
endif

SFLAGS     = $(GCCOPT) -D__COM32__ -D__FIRMWARE_$(FIRMWARE)__ 
LDFLAGS    = -m elf_$(ARCH) -shared --hash-style=gnu -T $(com32)/lib/$(ARCH)/elf.ld --as-needed
LIBGCC    := $(shell $(CC) $(GCCOPT) --print-libgcc)

LNXCFLAGS  = -I$(com32)/libutil/include -W -Wall -O -g -D_GNU_SOURCE
LNXSFLAGS  = -g
LNXLDFLAGS = -g

C_LIBS	   += $(objdir)/com32/libutil/libutil.c32 $(GPLLIB) \
	     $(objdir)/com32/lib/libcom32.c32
C_LNXLIBS  = $(objdir)/com32/libutil/libutil_lnx.a \
	     $(objdir)/com32/elflink/ldlinux/ldlinux_lnx.a

.SUFFIXES: .lss .c .o

.PRECIOUS: %.o
%.o: %.S
	$(CC) $(SFLAGS) -c -o $@ $<

.PRECIOUS: %.o
%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

.PRECIOUS: %.lo
%.lo: %.S
	$(CC) $(LNXSFLAGS) -c -o $@ $<

.PRECIOUS: %.lo
%.lo: %.c
	$(CC) $(LNXCFLAGS) -c -o $@ $<

.PRECIOUS: %.lnx
%.lnx: %.lo $(LNXLIBS) $(C_LNXLIBS)
	$(CC) $(LNXCFLAGS) -o $@ $^

.PRECIOUS: %.elf
%.elf: %.o $(C_LIBS)
	$(LD) $(LDFLAGS) -o $@ $^

%.c32: %.elf
	$(OBJCOPY) --strip-debug --strip-unneeded $< $@
