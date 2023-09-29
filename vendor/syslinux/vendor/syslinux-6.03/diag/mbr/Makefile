## -----------------------------------------------------------------------
##
##   Copyright 2007-2009 H. Peter Anvin - All Rights Reserved
##   Copyright 2009 Intel Corporation; author: H. Peter Anvin
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
##   Boston MA 02111-1307, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

#
# Makefile for MBR
#

mbrdir = $(topdir)/mbr
include $(MAKEDIR)/embedded.mk
VPATH = $(SRC)

all:	handoff.bin

%.o: %.S
	$(CC) $(MAKEDEPS) $(SFLAGS) -Wa,-a=$*.lst -c -o $@ $<

.PRECIOUS: %.elf
%.elf: %.o $(mbrdir)/mbr.ld
	$(LD) $(LDFLAGS) -T $(mbrdir)/$(ARCH)/mbr.ld -e _start -o $@ $<

%.bin: %.elf $(mbrdir)/checksize.pl
	$(OBJCOPY) -O binary $< $@
	$(PERL) checksize.pl $@
	$(CHMOD) -x $@

handoff.bin: handoff.elf $(mbrdir)/checksize.pl
	$(OBJCOPY) -O binary $< $@
	$(PERL) $(mbrdir)/checksize.pl $@ 420
	$(CHMOD) -x $@

mbr_bin.c: mbr.bin

tidy dist:
	rm -f *.o *.elf *.lst .*.d

clean: tidy

spotless: clean
	rm -f *.bin

-include .*.d
