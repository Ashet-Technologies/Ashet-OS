## -*- makefile -*- ------------------------------------------------------
##
##   Copyright 2001-2008 H. Peter Anvin - All Rights Reserved
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
##   Boston MA 02111-1307, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

##
## Make configuration for embedded directories
##

include $(MAKEDIR)/syslinux.mk

# Support IA32 and x86_64 platforms with one build
# Set up architecture specifics; for cross compilation, set ARCH as apt
# Initialize GCCOPT to null to begin with. Without this, make generates
# recursive error for GCCOPT
GCCOPT :=
ifeq ($(ARCH),i386)
	GCCOPT := $(call gcc_ok,-m32)
	GCCOPT += $(call gcc_ok,-march=i386)
	GCCOPT    += $(call gcc_ok,-mpreferred-stack-boundary=2,)
	GCCOPT    += $(call gcc_ok,-mincoming-stack-boundary=2,)
endif
ifeq ($(ARCH),x86_64)
	GCCOPT := $(call gcc_ok,-m64)
	GCCOPT += $(call gcc_ok,-march=x86-64)
	#let preferred-stack-boundary and incoming-stack-boundary be default(=4)
# Somewhere down the line ld barfs requiring -fPIC
	GCCOPT += $(call gcc_ok,-fPIC)
endif
GCCOPT    += $(call gcc_ok,-ffreestanding,)
GCCOPT	  += $(call gcc_ok,-fno-stack-protector,)
GCCOPT	  += $(call gcc_ok,-fwrapv,)
GCCOPT	  += $(call gcc_ok,-freg-struct-return,)
ifdef EFI_BUILD
GCCOPT    += -Os -fomit-frame-pointer -msoft-float
else
GCCOPT    += -Os -fomit-frame-pointer -mregparm=3 -DREGPARM=3 \
             -msoft-float
endif
GCCOPT    += $(call gcc_ok,-fno-exceptions,)
GCCOPT	  += $(call gcc_ok,-fno-asynchronous-unwind-tables,)
GCCOPT	  += $(call gcc_ok,-fno-strict-aliasing,)
GCCOPT	  += $(call gcc_ok,-falign-functions=0,-malign-functions=0)
GCCOPT    += $(call gcc_ok,-falign-jumps=0,-malign-jumps=0)
GCCOPT    += $(call gcc_ok,-falign-labels=0,-malign-labels=0)
GCCOPT    += $(call gcc_ok,-falign-loops=0,-malign-loops=0)
GCCOPT    += $(call gcc_ok,-fvisibility=hidden)

LIBGCC    := $(shell $(CC) $(GCCOPT) --print-libgcc)

LD        += -m elf_$(ARCH)

# Note: use += for CFLAGS and SFLAGS in case something is set in MCONFIG.local
CFLAGS    += $(GCCOPT) -g $(GCCWARN) -Wno-sign-compare $(OPTFLAGS) $(INCLUDES)
SFLAGS    += $(CFLAGS) -D__ASSEMBLY__

.SUFFIXES: .c .o .S .s .i .elf .com .bin .asm .lst .c32 .lss

%.o: %.c
	$(CC) $(MAKEDEPS) $(CFLAGS) -c -o $@ $<
%.i: %.c
	$(CC) $(MAKEDEPS) $(CFLAGS) -E -o $@ $<
%.s: %.c
	$(CC) $(MAKEDEPS) $(CFLAGS) -S -o $@ $<
%.o: %.S
	$(CC) $(MAKEDEPS) $(SFLAGS) -Wa,-a=$*.lst -c -o $@ $<
%.s: %.S
	$(CC) $(MAKEDEPS) $(SFLAGS) -E -o $@ $<
