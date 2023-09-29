## -----------------------------------------------------------------------
##
##   Copyright 2001-2008 H. Peter Anvin - All Rights Reserved
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
##   Boston MA 02110-1301, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

##
## Simple menu system
##

VPATH = $(SRC)
include $(MAKEDIR)/elf.mk

LNXLIBS	   = $(objdir)/com32/libutil/libutil_lnx.a

MODULES	  = menu.c32 vesamenu.c32
TESTFILES =

COMMONOBJS = menumain.o readconfig.o passwd.o drain.o \
		printmsg.o colors.o background.o refstr.o

all: $(MODULES) $(TESTFILES)

menu.elf : menu.o $(COMMONOBJS) $(C_LIBS)
	$(LD) $(LDFLAGS) -o $@ $^

vesamenu.elf : vesamenu.o $(COMMONOBJS) $(C_LIBS)
	$(LD) $(LDFLAGS) -o $@ $^

tidy dist:
	rm -f *.o *.lo *.a *.lst *.elf .*.d *.tmp

clean: tidy
	rm -f *.lnx

spotless: clean
	rm -f *.lss *.c32 *.com
	rm -f *~ \#*

install:

-include .*.d
