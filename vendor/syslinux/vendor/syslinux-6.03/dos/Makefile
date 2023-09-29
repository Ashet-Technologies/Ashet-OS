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
## MS-DOS FAT installer
##

include $(MAKEDIR)/embedded.mk

CFLAGS	+= -D__MSDOS__ -mregparm=3 -DREGPARM=3
# CFLAGS  += -DDEBUG

LDFLAGS	 = -T $(SRC)/dosexe.ld
OPTFLAGS = -g
INCLUDES = -include code16.h -nostdinc -iwithprefix include \
	   -I$(SRC) -I$(SRC)/.. -I$(SRC)/../libfat \
	   -I $(SRC)/../libinstaller -I $(SRC)/../libinstaller/getopt \
	   -I$(objdir)

SRCS     = syslinux.c \
	   ../libinstaller/fs.c \
	   ../libinstaller/syslxmod.c \
	   ../libinstaller/syslxopt.c \
	   ../libinstaller/setadv.c \
	   ../libinstaller/getopt/getopt_long.c \
	   ../libinstaller/bootsect_bin.c \
	   ../libinstaller/mbr_bin.c \
           $(wildcard $(SRC)/../libfat/*.c)
OBJS	 = header.o crt0.o ldlinux.o \
	   $(patsubst %.c,%.o,$(notdir $(SRCS)))
LIBOBJS	 = int2526.o conio.o memcpy.o memset.o memmove.o skipatou.o atou.o \
	   malloc.o free.o getopt_long.o getsetsl.o strchr.o strtoul.o \
	   strntoumax.o argv.o printf.o __divdi3.o __udivmoddi4.o

VPATH = $(SRC):$(SRC)/../libfat:$(SRC)/../libinstaller:$(SRC)/../libinstaller/getopt:$(OBJ)/../libinstaller

TARGETS = syslinux.com

all: $(TARGETS)

tidy dist:
	-rm -f *.o *.i *.s *.a .*.d *.tmp *.elf *.lst

clean: tidy

spotless: clean
	-rm -f *~ $(TARGETS)

installer:

syslinux.elf: $(OBJS) dosexe.ld libcom.a
	$(LD) $(LDFLAGS) -o $@ $(OBJS) libcom.a

libcom.a: $(LIBOBJS)
	-rm -f $@
	$(AR) cq $@ $^
	$(RANLIB) $@

syslinux.com: syslinux.elf
	$(OBJCOPY) -O binary $< $@
	$(UPX) --lzma --ultra-brute $@ || \
		$(UPX) --ultra-brute $@ || \
		true

%.com: %.asm
	$(NASM) $(NASMOPT) -f bin -o $@ -MP -MD .$@.d -l $*.lst $<

ldlinux.o: ldlinux.S $(OBJ)/../core/ldlinux.sys

-include .*.d
