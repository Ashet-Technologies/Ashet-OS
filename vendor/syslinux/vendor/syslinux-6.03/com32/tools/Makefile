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

VPATH = $(SRC)
include $(MAKEDIR)/build.mk

BINS    = relocs

INCLUDES += -I$(SRC)/include

all : $(BINS)

relocs : relocs.o
	$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)

tidy dist clean spotless:
	rm -f $(BINS)
	rm -f *.o *.a .*.d
	rm -f */*.o */*.a */.*.d

install installer:

-include .*.d */.*.d
