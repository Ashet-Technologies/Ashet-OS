## -----------------------------------------------------------------------
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
## samples for syslinux users
##

include $(MAKEDIR)/embedded.mk
VPATH = $(SRC)

PPMTOLSS16 = $(topdir)/utils/ppmtolss16

all: syslogo.lss

%.lss:	%.ppm.gz $(PPMTOLSS16)
	$(GZIPPROG) -cd $< | \
		$(PPMTOLSS16) \#000000=0 \#d0d0d0=7 \#f6f6f6=15	\
		> $@

%.ppm.gz: %.png
	$(PNGTOPNM) $< | gzip -9 > $@

tidy dist:
	rm -f *.o *.a *.lst *.elf .*.d

clean: tidy
	rm -f *.lss *.o *.c32 *.com

spotless: clean

-include .*.d
