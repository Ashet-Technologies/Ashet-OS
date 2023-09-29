## -----------------------------------------------------------------------
##
##   Copyright 2011 Intel Corporation; author: Matt Fleming
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
##   Boston MA 02111-1307, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

VPATH = $(SRC)
include $(MAKEDIR)/lib.mk
include $(MAKEDIR)/efi.mk

# Upstream gnu-efi has old-style function definitions.
CFLAGS += -Wno-strict-prototypes

CORE_CSRC := $(wildcard $(core)/*.c $(core)/*/*.c $(core)/*/*/*.c)
CORE_COBJ := $(subst $(core),$(OBJ)/../core/,$(patsubst %.c,%.o,$(CORE_CSRC)))

# We don't want to include any of the networking stack or the thread
# code since it will be implemented completely differently for EFI.
FILTERED_OBJS:= $(subst $(core),$(OBJ)/../core/,$(patsubst %.c,%.o, \
	$(wildcard $(core)/legacynet/*.c) \
	$(wildcard $(core)/fs/pxe/*.c) \
	$(wildcard $(core)/thread/*.c)))

# Don't include unit tests
FILTERED_OBJS += $(subst $(core),$(OBJ)/../core/, \
	$(patsubst %.c,%.o,$(shell find $(core) -path "*/tests/*.c" -print)))

# Don't include console objects
CORE_OBJS = $(filter-out %hello.o %rawcon.o %plaincon.o %strcasecmp.o %bios.o \
	%diskio_bios.o %ldlinux-c.o %isolinux-c.o %pxelinux-c.o \
	%localboot.o %pxeboot.o \
	$(FILTERED_OBJS),$(CORE_COBJ) $(CORE_SOBJ))

CORE_OBJS += $(addprefix $(OBJ)/../core/, \
	fs/pxe/pxe.o fs/pxe/tftp.o fs/pxe/urlparse.o fs/pxe/dhcp_option.o \
	fs/pxe/ftp.o fs/pxe/ftp_readdir.o fs/pxe/http.o fs/pxe/http_readdir.o)

LIB_OBJS = $(addprefix $(objdir)/com32/lib/,$(CORELIBOBJS)) \
	$(LIBEFI)

CSRC = $(wildcard $(SRC)/*.c)
OBJS = $(subst $(SRC)/,,$(filter-out %wrapper.o, $(patsubst %.c,%.o,$(CSRC))))

OBJS += $(objdir)/core/codepage.o $(ARCH)/linux.o

# The DATE is set on the make command line when building binaries for
# official release.  Otherwise, substitute a hex string that is pretty much
# guaranteed to be unique to be unique from build to build.
ifndef HEXDATE
HEXDATE := $(shell $(PERL) $(SRC)/../now.pl $(SRCS))
endif
ifndef DATE
DATE    := $(shell sh $(SRC)/../gen-id.sh $(VERSION) $(HEXDATE))
endif
CFLAGS		+= -DDATE_STR='"$(DATE)"'

.PHONY: subdirs
subdirs:
	mkdir -p $(ARCH)

$(OBJS): subdirs

# The targets to build in this directory
BTARGET  = syslinux.efi

syslinux.so: $(OBJS) $(CORE_OBJS) $(LIB_OBJS)
	$(LD) $(LDFLAGS) --strip-debug -o $@ $^ -lgnuefi -lefi

# We need to rename the .hash section because the EFI firmware
# linker really doesn't like it.
# $(OBJCOPY) --rename-section .gnu.hash=.sdata,load,data,alloc $^ $@
#syslinux.so: syslinux1.so
#	cp $^ $@

wrapper: wrapper.c
	$(CC) $^ -o $@

#
# Build the wrapper app and wrap our .so to produce a .efi
syslinux.efi: syslinux.so wrapper
	$(OBJ)/wrapper syslinux.so $@

all: $(BTARGET)

codepage.o: ../codepage/cp865.cp
	cp $(objdir)/../codepage/cp865.cp codepage.cp
	$(CC) $(SFLAGS) -c -o $@ $(core)/codepage.S

install:
	install -m 755 $(BTARGET) $(INSTALLROOT)$(AUXDIR)

strip:

tidy dist:
	rm -f *.so *.o wrapper
	find . \( -name \*.o -o -name \*.a -o -name .\*.d -o -name \*.tmp \) -print0 | \
		xargs -0r rm -f
	$(topdir)/efi/clean-gnu-efi.sh $(EFI_SUBARCH) $(objdir)

clean: tidy

spotless: clean
	rm -f $(BTARGET)
