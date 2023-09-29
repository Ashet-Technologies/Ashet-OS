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

VPATH = $(SRC)

include $(MAKEDIR)/embedded.mk

all:	mbr.bin   altmbr.bin   gptmbr.bin   isohdpfx.bin   isohdppx.bin \
	mbr_c.bin altmbr_c.bin gptmbr_c.bin isohdpfx_c.bin isohdppx_c.bin \
	mbr_f.bin altmbr_f.bin gptmbr_f.bin isohdpfx_f.bin isohdppx_f.bin

%.o: %.S
	$(CC) $(MAKEDEPS) $(SFLAGS) -Wa,-a=$*.lst -c -o $@ $<

%_c.o: %.S
	$(CC) $(MAKEDEPS) $(SFLAGS) -Wa,-a=$*_c.lst -DCTRL_80 -c -o $@ $<

%_f.o: %.S
	$(CC) $(MAKEDEPS) $(SFLAGS) -Wa,-a=$*_f.lst -DFORCE_80 -c -o $@ $<

.PRECIOUS: %.elf
#%.elf: %.o mbr.ld
%.elf: %.o $(SRC)/$(ARCH)/mbr.ld
	$(LD) $(LDFLAGS) -T $(SRC)/$(ARCH)/mbr.ld -e _start -o $@ $<

%.bin: %.elf $(SRC)/checksize.pl
	$(OBJCOPY) -O binary $< $@
	$(PERL) $(SRC)/checksize.pl $@
	$(CHMOD) -x $@

mbr_bin.c: mbr.bin

install:

tidy dist:
	rm -f *.o *.elf *.lst .*.d

clean: tidy

spotless: clean
	rm -f *.bin

-include .*.d
