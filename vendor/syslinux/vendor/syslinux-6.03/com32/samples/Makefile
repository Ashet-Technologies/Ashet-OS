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

LIBS = $(objdir)/com32/libutil/libutil.c32

VPATH = $(SRC)
include $(MAKEDIR)/elf.mk

all:	hello.c32 resolv.c32 serialinfo.c32 \
		localboot.c32 \
		fancyhello.c32 fancyhello.lnx \
		keytest.c32 keytest.lnx \
		advdump.c32 entrydump.c32

tidy dist:
	rm -f *.o *.lo *.a *.lst *.elf .*.d *.tmp

clean: tidy
	rm -f *.lnx

spotless: clean
	rm -f *.lss *.c32 *.com
	rm -f *~ \#*

install:	# Don't install samples

-include .*.d
