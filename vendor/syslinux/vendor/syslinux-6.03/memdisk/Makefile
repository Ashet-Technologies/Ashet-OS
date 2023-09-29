## -----------------------------------------------------------------------
##
##   Copyright 2001-2009 H. Peter Anvin - All Rights Reserved
##   Copyright 2009 Intel Corporation; author: H. Peter Anvin
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
##   Boston MA 02111-1307, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

include $(MAKEDIR)/embedded.mk
-include $(topdir)/version.mk

INCLUDES = -I$(topdir)/com32/include -I$(objdir)
CFLAGS  += -D__MEMDISK__ -DDATE='"$(DATE)"' -mregparm=3 -DREGPARM=3
LDFLAGS  = $(GCCOPT) -g
NASM     = nasm
NASMOPT  = -Ox
NFLAGS   = -dDATE='"$(DATE)"'
NINCLUDE = -I$(SRC)/

VPATH = $(SRC)
SRCS	 = $(wildcard *.asm *.c *.h)

# The DATE is set on the make command line when building binaries for
# official release.  Otherwise, substitute a hex string that is pretty much
# guaranteed to be unique to be unique from build to build.
ifndef HEXDATE
HEXDATE := $(shell $(PERL) $(SRC)/../now.pl $(SRCS))
endif
ifndef DATE
DATE    := $(shell sh $(SRC)/../gen-id.sh $(VERSION) $(HEXDATE))
endif

# Important: init.o16 must be first!!
OBJS16   = init.o16 init32.o
OBJS32   = start32.o setup.o msetup.o e820func.o conio.o memcpy.o memset.o \
	   memmove.o unzip.o dskprobe.o eltorito.o \
	   ctypes.o strntoumax.o strtoull.o suffix_number.o \
	   memdisk_chs_512.o memdisk_edd_512.o \
	   memdisk_iso_512.o memdisk_iso_2048.o

CSRC     = setup.c msetup.c e820func.c conio.c unzip.c dskprobe.c eltorito.c \
	   ctypes.c strntoumax.c strtoull.c suffix_number.c
SSRC     = start32.S memcpy.S memset.S memmove.S
NASMSRC  = memdisk_chs_512.asm memdisk_edd_512.asm \
	   memdisk_iso_512.asm memdisk_iso_2048.asm \
	   memdisk16.asm

all: memdisk # e820test

# tidy, clean removes everything except the final binary
tidy dist:
	rm -f *.o *.s *.tmp *.o16 *.s16 *.bin *.lst *.elf e820test .*.d
	rm -f *.map

clean: tidy

# spotless also removes the product binary
spotless: clean
	rm -f memdisk .depend

memdisk16.o: memdisk16.asm

# Cancel rule
%.o: %.asm

memdisk16.o: memdisk16.asm
	( $(NASM) -M -DDEPEND $(NFLAGS) $(NINCLUDE) -o $@ $< ; echo '' ) > .$@.d ; true
	$(NASM) -f elf $(NASMOPT) $(NFLAGS) $(NINCLUDE) -o $@ -l $*.lst $<

.PRECIOUS: %.bin
%.bin: %.asm
	( $(NASM) -M -DDEPEND $(NFLAGS) $(NINCLUDE) -o $@ $< ; echo '' ) > .$@.d ; true
	$(NASM) -f bin $(NASMOPT) $(NFLAGS) $(NINCLUDE) -o $@ -l $*.lst $<

memdisk_%.o: memdisk_%.bin
	$(LD) -r -b binary -o $@ $<

memdisk16.elf: $(OBJS16)
	$(LD) -Ttext 0 -o $@ $^

#memdisk32.elf: memdisk.ld $(OBJS32)
memdisk32.elf: $(ARCH)/memdisk.ld $(OBJS32)
	$(LD) -o $@ -T $^

%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

memdisk: memdisk16.bin memdisk32.bin postprocess.pl
	$(PERL) $(SRC)/postprocess.pl $@ memdisk16.bin memdisk32.bin

e820test: e820test.c e820func.c msetup.c
	$(CC) -m32 -g $(GCCWARN) -DTEST -o $@ $^

# This file contains the version number, so add a dependency for it
setup.s: ../version

# Include dependencies file
-include .*.d
