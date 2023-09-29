## -----------------------------------------------------------------------
##
##   Copyright 2001-2008 H. Peter Anvin - All Rights Reserved
##   Copyright 2009 Intel Corporation; author: H. Peter Anvin
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
##   Boston MA 02110-1301, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

##
## Hardware Detection Tool
##

VPATH = $(SRC)
include $(MAKEDIR)/elf.mk

LIBS      = $(objdir)/com32/libupload/libcom32upload.a
C_LIBS    += $(objdir)/com32/cmenu/libmenu/libmenu.c32
CFLAGS    += -I$(com32)/cmenu/libmenu -I$(com32)

MODULES	  = hdt.c32
TESTFILES =

OBJS	  = $(subst $(SRC)/,,$(patsubst %.c,%.o,$(wildcard $(SRC)/*.c)))
VERSION   = $(shell $(SED) -n 's/\#define VERSION \"\(.*\)\"/\1/p' hdt.h)
CODENAME  = $(shell $(SED) -n 's/\#define CODENAME \"\(.*\)\"/\1/p' hdt.h)
NODASH_VERSION = $(shell echo $(VERSION) | $(SED) -e 's/-/_/g' | $(SED) -e 's/\./_/g')
SUM_FILE  = hdt-$(VERSION).checksums

MEMTEST_URL = http://memtest.org/download/4.20/memtest86+-4.20.bin
MEMTEST     = memtest.bin

KERNEL_VERSION          ?= $(shell uname -r)
MODULES_ALIAS_FILE      ?= /lib/modules/$(KERNEL_VERSION)/modules.alias
GZ_MODULES_ALIAS_FILE   ?= modules.alias.gz
MODULES_PCIMAP_FILE     ?= /lib/modules/$(KERNEL_VERSION)/modules.pcimap
GZ_MODULES_PCIMAP_FILE  ?= modules.pcimap.gz
ISO_DIR                 ?= iso
ISOLINUX_DIR            ?= isolinux
FLOPPY_DIR		?= floppy
PCI_IDS_FILE            ?= $(PWD)/$(FLOPPY_DIR)/pci.ids
GZ_PCI_IDS_FILE         ?= $(PCI_IDS_FILE).gz
MENU_COM32              ?= $(com32)/menu/menu.c32
CHAIN_COM32             ?= $(com32)/chain/chain.c32
ART_DIR                 ?= art/
QEMU			?= qemu-kvm

all: $(MODULES) $(TESTFILES)

hdt.elf : $(OBJS) $(LIBS) $(C_LIBS)
	$(LD) $(LDFLAGS) -o $@ $^

memtest:
	-[ ! -f $(FLOPPY_DIR)/$(MEMTEST) ] && $(WGET) $(MEMTEST_URL) -O $(FLOPPY_DIR)/$(MEMTEST)

hdt.img: hdt.c32 $(FLOPPY_DIR)/hdt.cfg $(FLOPPY_DIR)/mtools.conf $(topdir)/mtools/syslinux $(MENU_COM32) memtest $(CHAIN_COM32)
	rm -f hdt*.img
	$(SED) -e 's/%VERSION%/$(VERSION)/g' $(FLOPPY_DIR)/hdt.cfg |\
	$(SED) -e 's/%CODENAME%/$(CODENAME)/g' > $(FLOPPY_DIR)/syslinux.cfg
	MTOOLSRC=$(PWD)/$(FLOPPY_DIR)/mtools.conf $(MFORMAT) -v HDT_$(NODASH_VERSION) -f 1440 -C a:
	$(topdir)/mtools/syslinux hdt.img
	-[ ! -f $(GZ_PCI_IDS_FILE) ] && cp /usr/share/hwdata/pci.ids $(PCI_IDS_FILE) && $(GZIPPROG) $(PCI_IDS_FILE)
	-[ ! -f $(GZ_PCI_IDS_FILE) ] && cp /usr/share/pci.ids $(PCI_IDS_FILE) && $(GZIPPROG) $(PCI_IDS_FILE)
	-[ -f $(MODULES_ALIAS_FILE) ] &&  cat $(MODULES_ALIAS_FILE) | $(GZIPPROG) - -f | MTOOLSRC=$(PWD)/$(FLOPPY_DIR)/mtools.conf $(MCOPY) - a:modules.alias
	-[ -f $(MODULES_PCIMAP_FILE) ] && cat $(MODULES_PCIMAP_FILE) | $(GZIPPROG) - -f | MTOOLSRC=$(PWD)/$(FLOPPY_DIR)/mtools.conf $(MCOPY) - a:modules.pcimap
	MTOOLSRC=$(PWD)/$(FLOPPY_DIR)/mtools.conf $(MCOPY) hdt.c32 a:
	MTOOLSRC=$(PWD)/$(FLOPPY_DIR)/mtools.conf $(MCOPY) $(MENU_COM32) a:
	MTOOLSRC=$(PWD)/$(FLOPPY_DIR)/mtools.conf $(MCOPY) $(CHAIN_COM32) a:
	@ [ -f $(GZ_PCI_IDS_FILE) ] && MTOOLSRC=$(PWD)/$(FLOPPY_DIR)/mtools.conf $(MCOPY) $(GZ_PCI_IDS_FILE) a:pci.ids || printf "\nThe $(GZ_PCI_IDS_FILE) file is missing and can be downloaded from http://pciids.sourceforge.net and gzipped in\nthe ./com32/hdt/$(FLOPPY_DIR) directory of the extracted Syslinux source.\n\n"
	MTOOLSRC=$(PWD)/$(FLOPPY_DIR)/mtools.conf $(MCOPY) $(FLOPPY_DIR)/syslinux.cfg a:
	MTOOLSRC=$(PWD)/$(FLOPPY_DIR)/mtools.conf $(MCOPY) $(FLOPPY_DIR)/$(MEMTEST) a:
	MTOOLSRC=$(PWD)/$(FLOPPY_DIR)/mtools.conf $(MCOPY) $(ART_DIR)/backgnd.png a:
	MTOOLSRC=$(PWD)/$(FLOPPY_DIR)/mtools.conf $(MCOPY) $(ART_DIR)/display.png a:
	MTOOLSRC=$(PWD)/$(FLOPPY_DIR)/mtools.conf $(MCOPY) $(ART_DIR)/red.png a:
	mv hdt.img hdt-$(VERSION).img
	ln -sf hdt-$(VERSION).img hdt.img

hdt.img.gz: hdt.img
	rm -rf hdt*.img.gz
	$(GZIPPROG) -c hdt-$(VERSION).img >hdt-$(VERSION).img.gz
	ln -sf hdt-$(VERSION).img.gz hdt.img.gz

hdt.iso: hdt.c32 $(topdir)/core/isolinux.bin $(FLOPPY_DIR)/hdt.cfg memtest
	rm -rf $(ISO_DIR)
	rm -f hdt.iso
	mkdir -p $(ISO_DIR)/$(ISOLINUX_DIR)
	cp $(topdir)/core/isolinux.bin $(ISO_DIR)/$(ISOLINUX_DIR)
	$(SED) -e 's/%VERSION%/$(VERSION)/g' $(FLOPPY_DIR)/hdt.cfg |\
		$(SED) -e 's/%CODENAME%/$(CODENAME)/g' > $(ISO_DIR)/$(ISOLINUX_DIR)/isolinux.cfg
	cp hdt.c32 $(ISO_DIR)/$(ISOLINUX_DIR)
	cp $(FLOPPY_DIR)/$(MEMTEST) $(ISO_DIR)/$(ISOLINUX_DIR)
	cp $(MENU_COM32) $(ISO_DIR)/$(ISOLINUX_DIR)
	cp $(CHAIN_COM32) $(ISO_DIR)/$(ISOLINUX_DIR)
	cp -av $(ART_DIR)/backgnd.png $(ISO_DIR)/$(ISOLINUX_DIR)
	cp -av $(ART_DIR)/display.png $(ISO_DIR)/$(ISOLINUX_DIR)
	cp -av $(ART_DIR)/red.png $(ISO_DIR)/$(ISOLINUX_DIR)
	-[ ! -f $(GZ_PCI_IDS_FILE) ] && cp /usr/share/hwdata/pci.ids $(PCI_IDS_FILE) && $(GZIPPROG) $(PCI_IDS_FILE)
	-[ ! -f $(GZ_PCI_IDS_FILE) ] && cp /usr/share/pci.ids $(PCI_IDS_FILE) && $(GZIPPROG) $(PCI_IDS_FILE)
	-[ -f $(MODULES_ALIAS_FILE) ] && cp $(MODULES_ALIAS_FILE) $(ISO_DIR)/$(ISOLINUX_DIR)\
	       	&& $(GZIPPROG) $(ISO_DIR)/$(ISOLINUX_DIR)/modules.alias\
		&& mv $(ISO_DIR)/$(ISOLINUX_DIR)/modules.alias.gz $(ISO_DIR)/$(ISOLINUX_DIR)/modules.alias
	-[ -f $(MODULES_PCIMAP_FILE) ] && cp $(MODULES_PCIMAP_FILE) $(ISO_DIR)/$(ISOLINUX_DIR)\
		&& $(GZIPPROG) $(ISO_DIR)/$(ISOLINUX_DIR)/modules.pcimap\
		&& mv $(ISO_DIR)/$(ISOLINUX_DIR)/modules.pcimap.gz $(ISO_DIR)/$(ISOLINUX_DIR)/modules.pcimap
	-[ ! -f $(ISO_DIR)/$(ISOLINUX_DIR)/pci.ids.gz ] && cp $(GZ_PCI_IDS_FILE) $(ISO_DIR)/$(ISOLINUX_DIR)/pci.ids
	-[ ! -f $(ISO_DIR)/$(ISOLINUX_DIR)/pci.ids ] && printf "\nThe $(FLOPPY_DIR)/pci.ids file is missing and can be downloaded from http://pciids.sourceforge.net and put in\nthe ./com32/hdt/$(FLOPPY_DIR) directory of the extracted Syslinux source.\n\n"
	$(MKISOFS) -o hdt.iso -b $(ISOLINUX_DIR)/isolinux.bin -c $(ISOLINUX_DIR)/boot.cat \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		$(ISO_DIR)
	mv hdt.iso hdt-$(VERSION).iso
	ln -sf hdt-$(VERSION).iso hdt.iso

hdt-hybrid.iso: hdt.iso ../../utils/isohybrid
	cp hdt-$(VERSION).iso hdt-hybrid-$(VERSION).iso
	../../utils/isohybrid --partok hdt-hybrid-$(VERSION).iso
	ln -sf hdt-hybrid-$(VERSION).iso hdt-hybrid.iso

release: spotless hdt.c32 hdt.img hdt.img.gz hdt.iso hdt-hybrid.iso
	mv hdt.c32 hdt_$(NODASH_VERSION).c32
	md5sum hdt_$(NODASH_VERSION).c32 >$(SUM_FILE)
	md5sum hdt-$(VERSION).iso >>$(SUM_FILE)
	md5sum hdt-hybrid-$(VERSION).iso >>$(SUM_FILE)
	md5sum hdt-$(VERSION).img >>$(SUM_FILE)
	md5sum hdt-$(VERSION).img.gz >>$(SUM_FILE)

test: hdt.img
	$(QEMU) -fda hdt.img

tidy dist:
	rm -f *.o *.lo *.a *.lst *.elf .*.d *.tmp

clean: tidy
	rm -f *.lnx

spotless: clean
	rm -f *.lss *.c32 *.com hdt*.img hdt*.iso hdt*.img.gz
	rm -rf $(ISO_DIR)
	rm -rf $(FLOPPY_DIR)/$(MEMTEST)
	rm -rf $(FLOPPY_DIR)/pci.ids*
	rm -rf hdt-*checksums
	rm -f *~ \#*

install:

-include .*.d
