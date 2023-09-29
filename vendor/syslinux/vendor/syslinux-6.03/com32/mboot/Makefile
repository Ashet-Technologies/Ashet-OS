## -----------------------------------------------------------------------
##
##   Copyright 2001-2009 H. Peter Anvin - All Rights Reserved
##   Copyright 2009 Intel Corporation; author: H. Peter Anvin
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
##   Boston MA 02110-1301, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

##
## Multiboot module
##

VPATH = $(SRC)
include $(MAKEDIR)/elf.mk

LNXLIBS	   = $(objdir)/com32/libutil/libutil_lnx.a

MODULES	  = mboot.c32
TESTFILES =

OBJS = mboot.o map.o mem.o initvesa.o apm.o solaris.o syslinux.o

all: $(MODULES) $(TESTFILES)

mboot.elf : $(OBJS) $(C_LIBS)
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
