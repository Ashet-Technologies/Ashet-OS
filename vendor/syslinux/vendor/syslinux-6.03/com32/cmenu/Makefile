## -----------------------------------------------------------------------
##
##   Copyright 2001-2009 H. Peter Anvin - All Rights Reserved
##   Copyright 2009 Intel Corporation; author: H. Peter Anvin
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
##   Boston MA 02111-1307, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

##
## Makefile for the complex menu system
##

NOGPL := 1

LIBS  = libmenu/libmenu.c32 \
        $(objdir)/com32/libutil/libutil.c32 \
        $(objdir)/com32/lib/libcom32.c32

C_LIBS	  = libmenu/libmenu.c32

VPATH = $(SRC)
include $(MAKEDIR)/elf.mk

CFLAGS	  += -I$(SRC)/libmenu

LIBMENU = libmenu/syslnx.o libmenu/com32io.o libmenu/tui.o \
	libmenu/menu.o libmenu/passwords.o libmenu/des.o libmenu/help.o \
	$(objdir)/com32/libutil/libutil.c32 $(objdir)/com32/lib/libcom32.c32

CMENUS = $(patsubst %.c,%.c32,$(wildcard $(SRC)/*.c))
IMENUS = $(patsubst %.menu,%.c32,$(wildcard $(SRC)/*.menu))

MENUS = $(LIBS) $(subst $(SRC)/,,$(CMENUS) $(IMENUS))

.SUFFIXES: .S .c .o .elf .c32 .menu

.PRECIOUS: %.c
%.c: %.menu adv_menu.tpl
	$(PYTHON) $(SRC)/menugen.py --input=$< --output=$@ --template=$(SRC)/adv_menu.tpl

all:	makeoutputdirs menus

makeoutputdirs:
	@mkdir -p $(OBJ)/libmenu

libmenu/libmenu.elf: $(LIBMENU)
	$(LD) -shared $(LDFLAGS) -soname $(patsubst %.elf,%.c32,$(@F)) \
		-o $@ $^

tidy dist:
	rm -f *.o *.lo *.lst *.elf */*.o */*.elf .*.d */.*.d

libclean:
	rm -f libmenu/*.c32

clean: tidy menuclean
	rm -f *.lss *.com

menuclean:
	rm -f $(patsubst %.menu,%.c,$(wildcard *.menu))

spotless: clean libclean menuclean
	rm -f *~ \#* *.c32

menus: $(MENUS)

install:	# Don't install samples

-include .*.d */.*.d
