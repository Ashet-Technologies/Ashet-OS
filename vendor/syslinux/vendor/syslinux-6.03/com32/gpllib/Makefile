#
# LGPL/GPL code library
#

# Include configuration rules
include $(MAKEDIR)/lib.mk

REQFLAGS += -I$(SRC)/../gplinclude -I$(SRC)/../gplinclude/zzjson

GPLDIRS := $(SRC) $(addprefix $(SRC)/,disk dmi vpd acpi zzjson)
LIBOBJS := $(subst $(SRC)/,,$(foreach dir,$(GPLDIRS),$(patsubst %.c,%.o,$(wildcard $(dir)/*.c))))

BINDIR   = /usr/bin
LIBDIR   = /usr/lib
DATADIR  = /usr/share
AUXDIR   = $(DATADIR)/syslinux
INCDIR   = /usr/include
COM32DIR = $(AUXDIR)/com32

all: makeoutputdirs libgpl.c32

makeoutputdirs:
	@mkdir -p $(foreach b, \
		$(addprefix $(OBJ),$(sort $(dir $(LIBOBJS)))),$(b))

libgpl.elf : $(LIBOBJS)
	$(LD) -shared $(LDFLAGS) -soname $(patsubst %.elf,%.c32,$(@F)) -o $@ $^

tidy dist clean:
	find . \( -name \*.o -o -name .\*.d -o -name \*.tmp \) -print0 | \
		xargs -0r rm -f

spotless: clean
	rm -f *.c32
	rm -f *~ \#* */*~ */\#*

# Mixing in the GPL include files is suboptimal, but I'm not sure
# there is a better way to do it.
install: all
	mkdir -m 755 -p $(INSTALLROOT)$(COM32DIR)
	install -m 644 libgpl.c32 $(INSTALLROOT)$(COM32DIR)
	mkdir -p $(INSTALLROOT)$(COM32DIR)/include/
	cp -r $(SRC)/../gplinclude $(INSTALLROOT)$(COM32DIR)/include/

-include .*.d */.*.d */*/.*.d
