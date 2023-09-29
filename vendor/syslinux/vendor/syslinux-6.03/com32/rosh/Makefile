## -----------------------------------------------------------------------
##
##   Copyright 2001-2008 H. Peter Anvin - All Rights Reserved
##   Copyright 2010 Intel Corporation; author: H. Peter Anvin
##   Copyright 2008-2010 Gene Cumm - All Rights Reserved
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
##   Boston MA 02111-1307, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

##
## ROSH Read Only Shell
##

LIBS = $(objdir)/com32/libutil/libutil.c32 \
	$(objdir)/com32/lib/libcom32.c32

VPATH = $(SRC)
include $(MAKEDIR)/rosh.mk

# from com32/sysdump/Makefile
# The DATE is set on the make command line when building binaries for
# official release.  Otherwise, substitute a hex string that is pretty much
# guaranteed to be unique to be unique from build to build.
ifndef HEXDATE
HEXDATE := $(shell $(PERL) $(topdir)/now.pl $(SRCS) $(wildcard *.h))
endif
ifndef DATE
DATE    := $(shell sh $(topdir)/gen-id.sh $(VERSION) $(HEXDATE))
endif

CFLAGS		+= -DDATE='"$(DATE)"'
LNXCFLAGS	+= -DDATE='"$(DATE)"'

all:	rosh.c32

rosh.o:	rosh.h

rosh.lo:	rosh.h

allgrc:	rosh.c32 rosh.lnx

tidy dist:
	rm -f *.o *.lo *.a *.lst *.elf .*.d *.tmp

clean: tidy
	rm -f *.lnx

spotless: clean
	rm -f *.lss *.c32 *.com
	rm -f *~ \#*

install:

-include .*.d
