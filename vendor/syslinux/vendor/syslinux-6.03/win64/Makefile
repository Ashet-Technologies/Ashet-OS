## -----------------------------------------------------------------------
##
##   Copyright 1998-2008 H. Peter Anvin - All Rights Reserved
##   Copyright 2010 Intel Corporation; author: H. Peter Anvin
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
##   Boston MA 02111-1307, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

#
# Makefile for SYSLINUX Win64
#
# This is separated out mostly so we can have a different set of Makefile
# variables.
#

OSTYPE   = $(shell uname -msr)
# Don't know how to do a native compile here...
WINPREFIX  := $(shell $(SRC)/find-mingw64.sh gcc)
WINCFLAGS  := $(GCCWARN) -Wno-sign-compare -Os -fomit-frame-pointer \
	      -D_FILE_OFFSET_BITS=64
WINLDFLAGS := -Os -s

WINCFLAGS += -I$(SRC) -I$(SRC)/../win -I$(objdir) \
	     -I$(SRC)/../libfat -I$(SRC)/../libinstaller \
	     -I$(SRC)/../libinstaller/getopt

WINCC      := $(WINPREFIX)gcc
WINAR	   := $(WINPREFIX)ar
WINRANLIB  := $(WINPREFIX)ranlib

WINCC_IS_GOOD := $(shell $(WINCC) $(WINCFLAGS) $(WINLDFLAGS) \
	-o hello.exe $(SRC)/../win/hello.c >/dev/null 2>&1 ; echo $$?)

.SUFFIXES: .c .obj .lib .exe .i .s .S

SRCS     = ../win/syslinux.c ../win/ntfssect.c
OBJS     = $(patsubst %.c,%.obj,$(notdir $(SRCS)))
LIBSRC   = ../libinstaller/fs.c \
	   ../libinstaller/syslxmod.c \
	   ../libinstaller/syslxopt.c \
	   ../libinstaller/setadv.c \
	   ../libinstaller/getopt/getopt_long.c \
	   ../libinstaller/bootsect_bin.c \
	   ../libinstaller/ldlinux_bin.c \
	   ../libinstaller/ldlinuxc32_bin.c \
	   ../libinstaller/mbr_bin.c \
	   $(wildcard $(SRC)/../libfat/*.c)
LIBOBJS  = $(patsubst %.c,%.obj,$(notdir $(LIBSRC)))

LIB	 = syslinux.lib

VPATH = $(SRC):$(SRC)/../win:$(SRC)/../libfat:$(SRC)/../libinstaller:$(SRC)/../libinstaller/getopt:$(OBJ)/../libinstaller

TARGETS = syslinux64.exe

ifeq ($(WINCC_IS_GOOD),0)
all: $(TARGETS)
else
all:
	rm -f $(TARGETS)
endif

tidy dist:
	-rm -f *.o *.obj *.lib *.i *.s *.a .*.d *.tmp *_bin.c hello.exe

clean: tidy

spotless: clean
	-rm -f *~ $(TARGETS)

installer:

$(LIB): $(LIBOBJS)
	rm -f $@
	$(WINAR) cq $@ $^
	$(WINRANLIB) $@

syslinux64.exe: $(OBJS) $(LIB)
	$(WINCC) $(WINLDFLAGS) -o $@ $^


%.obj: %.c
	$(WINCC) $(UMAKEDEPS) $(WINCFLAGS) -c -o $@ $<
%.i: %.c
	$(WINCC) $(UMAKEDEPS) $(WINCFLAGS) -E -o $@ $<
%.s: %.c
	$(WINCC) $(UMAKEDEPS) $(WINCFLAGS) -S -o $@ $<

-include .*.d
