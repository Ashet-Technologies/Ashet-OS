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

MODULES = 
TESTFILES =

all: $(MODULES) $(TESTFILES)

test_memalign.elf : test_memalign.o  $(LIBS) $(C_LIBS)
	$(LD) $(LDFLAGS) -o $@ $^

test_com32.elf: CFLAGS += -DELF_DEBUG
test_com32.elf: test_com32.o ../lib/libcom32min.a $(LIBGCC)
	$(LD) -n $(LDFLAGS) -o $@ test_com32.o $(LIBGCC) --whole-archive ../lib/libcom32min.a -Map test_com32.map

tidy dist:
	rm -f *.o *.lo *.a *.lst *.elf .*.d *.map

clean: tidy
	rm -f *.lss *.c32 *.lnx *.com

spotless: clean
	rm -f *~ \#*

install:

-include .*.d
