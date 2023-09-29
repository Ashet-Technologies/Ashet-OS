# Include configuration rules
VPATH = $(SRC)
include $(MAKEDIR)/com32.mk

REQFLAGS += -I$(SRC)

LIBOBJS := $(notdir $(patsubst %.c,%.o,$(wildcard $(SRC)/*.c)))

BINDIR   = /usr/bin
LIBDIR   = /usr/lib
DATADIR  = /usr/share
AUXDIR   = $(DATADIR)/syslinux
INCDIR   = /usr/include
COM32DIR = $(AUXDIR)/com32

all: libcom32upload.a

libcom32upload.a : $(LIBOBJS)
	rm -f $@
	$(AR) cq $@ $^
	$(RANLIB) $@

tidy dist clean:
	find . \( -name \*.o -o -name \*.a -o -name .\*.d -o -name \*.tmp \) -print0 | \
		xargs -0r rm -f

spotless: clean
	rm -f *.a
	rm -f *~ \#* */*~ */\#*

install: all
	mkdir -m 755 -p $(INSTALLROOT)$(COM32DIR)
	install -m 644 libcom32upload.a $(INSTALLROOT)$(COM32DIR)
	mkdir -p $(INSTALLROOT)$(COM32DIR)/include/
	cp -r $(SRC)/*.h $(INSTALLROOT)$(COM32DIR)/include/

-include .*.d */.*.d */*/.*.d
