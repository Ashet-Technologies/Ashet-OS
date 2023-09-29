## -----------------------------------------------------------------------
##
##   Copyright 2001-2009 H. Peter Anvin - All Rights Reserved
##   Copyright 2009-2010 Intel Corporation; author: H. Peter Anvin
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
##   Boston MA 02110-1301, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

##
## Lua Makefile
##

VPATH = $(SRC)
include $(MAKEDIR)/elf.mk

LNXLIBS	   = 

# Temporarily allow warnings not being treated as errors
#GCCWARN	  += -Wno-error

CFLAGS    += -DSYSLINUX
MODULES	  = lua.c32
MODULES   += cpu.c32
MODULES   += dhcp.c32
MODULES   += dmi.c32
MODULES   += lfs.c32
MODULES   += pci.c32
MODULES   += syslinux.c32
MODULES   += vesa.c32
MODULES   += cmenu.c32
TESTFILES =

OBJS	  = lua.o

LIBLUA    = liblua.c32

LIBLUA_OBJS := lapi.o lcode.o lctype.o ldebug.o ldo.o ldump.o lfunc.o
LIBLUA_OBJS += lgc.o llex.o lmem.o lobject.o lopcodes.o lparser.o
LIBLUA_OBJS += lstate.o lstring.o ltable.o ltm.o lundump.o lvm.o lzio.o

LIBLUA_OBJS += lauxlib.o lbaselib.o lbitlib.o lcorolib.o ldblib.o liolib.o
LIBLUA_OBJS += loslib.o lstrlib.o ltablib.o loadlib.o linit.o

CFLAGS += -DLUA_ANSI

all: $(MODULES) $(TESTFILES)

liblua.elf : $(LIBLUA_OBJS)
	$(LD) $(LDFLAGS) -shared -soname $(patsubst %.elf,%.c32,$(@F)) \
		-o $@ $^

lua.elf : $(OBJS) $(LIBLUA) $(C_LIBS)
	$(LD) $(LDFLAGS) -o $@ $^

cmenu.o : CFLAGS += -I$(com32)/cmenu/libmenu
cmenu.elf : $(objdir)/com32/cmenu/libmenu/libmenu.c32

tidy dist:
	rm -f *.o *.lo *.lst *.elf .*.d *.tmp

clean: tidy
	rm -f *.lnx

spotless: clean
	rm -f *.lss *.c32 *.com
	rm -f *~ \#*

install:

-include .*.d
