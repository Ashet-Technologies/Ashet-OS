## -----------------------------------------------------------------------
##
##   Copyright 1998-2009 H. Peter Anvin - All Rights Reserved
##   Copyright 2009-2014 Intel Corporation; author: H. Peter Anvin
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
##   Boston MA 02111-1307, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

#
# Main Makefile for SYSLINUX
#

all_firmware := bios efi32 efi64

#
# topdir is only set when we are doing a recursive make. Do a bunch of
# initialisation if it's unset since this is the first invocation.
#
ifeq ($(topdir),)

topdir = $(CURDIR)

#
# Because we need to build modules multiple times, e.g. for BIOS,
# efi32, efi64, we output all object and executable files to a
# separate object directory for each firmware.
#
# The output directory can be customised by setting the O=/obj/path/
# variable when invoking make. If no value is specified the default
# directory is the top-level of the Syslinux source.
#
ifeq ("$(origin O)", "command line")
	OBJDIR := $(O)
else
	OBJDIR = $(topdir)
endif

# If the output directory does not exist we bail because that is the
# least surprising thing to do.
cd-output := $(shell cd $(OBJDIR) && /bin/pwd)
$(if $(cd-output),, \
	$(error output directory "$(OBJDIR)" does not exist))

#
# These environment variables are exported to every invocation of
# make,
#
# 'topdir' - the top-level directory containing the Syslinux source
# 'objdir' - the top-level directory of output files for this firmware
# 'MAKEDIR' - contains Makefile fragments
# 'OBJDIR' - the top-level directory of output files
#
# There are also a handful of variables that are passed to each
# sub-make,
#
# SRC - source tree location of the module being compiled
# OBJ - output tree location of the module being compiled
#
# A couple of rules for writing Makefiles,
#
# - Do not use relative paths, use the above variables
# - You can write $(SRC) a lot less if you add it to VPATH
#

MAKEDIR = $(topdir)/mk
export MAKEDIR topdir OBJDIR

include $(MAKEDIR)/syslinux.mk
-include $(OBJDIR)/version.mk

private-targets = prerel unprerel official release burn isolinux.iso \
		  preupload upload test unittest regression spotless

ifeq ($(MAKECMDGOALS),)
	MAKECMDGOALS += all
endif

#
# The 'bios', 'efi32' and 'efi64' are dummy targets. Their only
# purpose is to instruct us which output directories need
# creating. Which means that we always need a *real* target, such as
# 'all', appended to the make goals.
#
firmware = $(all_firmware)
real-target := $(filter-out $(firmware), $(MAKECMDGOALS))
real-firmware := $(filter $(firmware), $(MAKECMDGOALS))

ifeq ($(real-target),)
	real-target = all
endif

ifeq ($(real-firmware),)
	real-firmware = $(firmware)
endif

.PHONY: $(filter-out $(private-targets), $(MAKECMDGOALS))
$(filter-out $(private-targets), $(MAKECMDGOALS)):
	$(MAKE) -C $(OBJDIR) -f $(CURDIR)/Makefile SRC="$(topdir)" \
		OBJ=$(OBJDIR) objdir=$(OBJDIR) $(MAKECMDGOALS)

unittest:
	printf "Executing unit tests\n"
	$(MAKE) -C core/mem/tests all
	$(MAKE) -C com32/lib/syslinux/tests all

regression:
	$(MAKE) -C tests SRC="$(topdir)/tests" OBJ="$(topdir)/tests" \
		objdir=$(OBJDIR) \
		-f $(topdir)/tests/Makefile all

test: unittest regression

# Hook to add private Makefile targets for the maintainer.
-include $(topdir)/Makefile.private

else # ifeq ($(topdir),)

include $(MAKEDIR)/syslinux.mk

# Hook to add private Makefile targets for the maintainer.
-include $(topdir)/Makefile.private

#
# The BTARGET refers to objects that are derived from ldlinux.asm; we
# like to keep those uniform for debugging reasons; however, distributors
# want to recompile the installers (ITARGET).
#
# BOBJECTS and IOBJECTS are the same thing, except used for
# installation, so they include objects that may be in subdirectories
# with their own Makefiles.  Finally, there is a list of those
# directories.
#

ifndef EFI_BUILD
MODULES = memdisk/memdisk \
	com32/menu/*.c32 com32/modules/*.c32 com32/mboot/*.c32 \
	com32/hdt/*.c32 com32/rosh/*.c32 com32/gfxboot/*.c32 \
	com32/sysdump/*.c32 com32/lua/src/*.c32 com32/chain/*.c32 \
	com32/lib/*.c32 com32/libutil/*.c32 com32/gpllib/*.c32 \
	com32/elflink/ldlinux/*.c32 com32/cmenu/libmenu/*.c32
else
# FIXME: Prune other BIOS-centric modules
MODULES = com32/menu/*.c32 com32/modules/*.c32 com32/mboot/*.c32 \
	com32/hdt/*.c32 com32/rosh/*.c32 com32/gfxboot/*.c32 \
	com32/sysdump/*.c32 com32/lua/src/*.c32 com32/chain/*.c32 \
	com32/lib/*.c32 com32/libutil/*.c32 com32/gpllib/*.c32 \
	com32/cmenu/libmenu/*.c32 com32/elflink/ldlinux/$(LDLINUX)
endif

# List of module objects that should be installed for all derivatives
INSTALLABLE_MODULES = $(MODULES)

# syslinux.exe is BTARGET so as to not require everyone to have the
# mingw suite installed
BTARGET  = version.gen version.h $(OBJDIR)/version.mk
BOBJECTS = $(BTARGET) \
	mbr/*.bin \
	core/pxelinux.0 core/lpxelinux.0 \
	core/isolinux.bin core/isolinux-debug.bin \
	gpxe/gpxelinux.0 dos/syslinux.com \
	win32/syslinux.exe win64/syslinux64.exe \
	dosutil/*.com dosutil/*.sys \
	$(MODULES)

# BSUBDIRs build the on-target binary components.
# ISUBDIRs build the installer (host) components.
#
# Note: libinstaller is both a BSUBDIR and an ISUBDIR.  It contains
# files that depend only on the B phase, but may have to be regenerated
# for "make installer".

ifdef EFI_BUILD

BSUBDIRS = codepage com32 lzo core mbr sample efi txt
ISUBDIRS =

INSTALLSUBDIRS = efi

NETINSTALLABLE = efi/syslinux.efi $(INSTALLABLE_MODULES)

else

BSUBDIRS = codepage com32 lzo core memdisk mbr gpxe sample \
	   diag libinstaller dos win32 win64 dosutil txt

ITARGET  =
IOBJECTS = $(ITARGET) \
	utils/gethostip utils/isohybrid utils/mkdiskimage \
	mtools/syslinux linux/syslinux extlinux/extlinux
ISUBDIRS = libinstaller mtools linux extlinux utils

# Things to install in /usr/bin
INSTALL_BIN   =	mtools/syslinux
# Things to install in /sbin
INSTALL_SBIN  = extlinux/extlinux
# Things to install in /usr/lib/syslinux
INSTALL_AUX   =	core/pxelinux.0 gpxe/gpxelinux.0 gpxe/gpxelinuxk.0 \
		core/isolinux.bin core/isolinux-debug.bin \
		dos/syslinux.com core/lpxelinux.0 \
		mbr/*.bin $(INSTALLABLE_MODULES)
INSTALL_AUX_OPT = win32/syslinux.exe win64/syslinux64.exe
INSTALL_DIAG  =	diag/mbr/handoff.bin \
		diag/geodsp/geodsp1s.img.xz diag/geodsp/geodspms.img.xz

# These directories manage their own installables
INSTALLSUBDIRS = com32 utils dosutil

# Things to install in /boot/extlinux
EXTBOOTINSTALL = $(INSTALLABLE_MODULES)

# Things to install in /tftpboot
NETINSTALLABLE = core/pxelinux.0 gpxe/gpxelinux.0 core/lpxelinux.0 \
		 $(INSTALLABLE_MODULES)

endif # ifdef EFI_BUILD

.PHONY: subdirs $(BSUBDIRS) $(ISUBDIRS) test

ifeq ($(HAVE_FIRMWARE),)

firmware = $(all_firmware)

# If no firmware was specified the rest of MAKECMDGOALS applies to all
# firmware.
ifeq ($(filter $(firmware),$(MAKECMDGOALS)),)
all strip tidy clean dist install installer netinstall: $(all_firmware)

else

# Don't do anything for the rest of MAKECMDGOALS at this level. It
# will be handled for each of $(firmware).
strip tidy clean dist install installer netinstall:

endif

# Convert 'make bios strip' to 'make strip', etc for rest of the Makefiles.
MAKECMDGOALS := $(filter-out $(firmware),$(MAKECMDGOALS))
ifeq ($(MAKECMDGOALS),)
	MAKECMDGOALS += all
endif

#
# You'd think that we'd be able to use the 'define' directive to
# abstract the code for invoking make(1) in the output directory, but
# by using 'define' we lose the ability to build in parallel.
#
.PHONY: $(firmware)
bios:
	@mkdir -p $(OBJ)/bios
	$(MAKE) -C $(OBJ)/bios -f $(SRC)/Makefile SRC="$(SRC)" \
		objdir=$(OBJ)/bios OBJ=$(OBJ)/bios HAVE_FIRMWARE=1 \
		FIRMWARE=BIOS \
		ARCH=i386 LDLINUX=ldlinux.c32 $(MAKECMDGOALS)

efi32:
	@mkdir -p $(OBJ)/efi32
	$(MAKE) -C $(OBJ)/efi32 -f $(SRC)/Makefile SRC="$(SRC)" \
		objdir=$(OBJ)/efi32 OBJ=$(OBJ)/efi32 HAVE_FIRMWARE=1 \
		ARCH=i386 BITS=32 EFI_BUILD=1 LDLINUX=ldlinux.e32 \
		FIRMWARE=EFI32 \
		$(MAKECMDGOALS)

efi64:
	@mkdir -p $(OBJ)/efi64
	$(MAKE) -C $(OBJ)/efi64 -f $(SRC)/Makefile SRC="$(SRC)" \
		objdir=$(OBJ)/efi64 OBJ=$(OBJ)/efi64 HAVE_FIRMWARE=1 \
		ARCH=x86_64 BITS=64 EFI_BUILD=1 LDLINUX=ldlinux.e64 \
		FIRMWARE=EFI64 \
		$(MAKECMDGOALS)

else # ifeq($(HAVE_FIRMWARE),)

all: all-local subdirs

all-local: $(BTARGET) $(ITARGET)
	-ls -l $(BOBJECTS) $(IOBJECTS)
subdirs: $(BSUBDIRS) $(ISUBDIRS)

$(sort $(ISUBDIRS) $(BSUBDIRS)):
	@mkdir -p $@
	$(MAKE) -C $@ SRC="$(SRC)/$@" OBJ="$(OBJ)/$@" \
		-f $(SRC)/$@/Makefile $(MAKECMDGOALS)

$(ITARGET):
	@mkdir -p $@
	$(MAKE) -C $@ SRC="$(SRC)/$@" OBJ="$(OBJ)/$@" \
		-f $(SRC)/$@/Makefile $(MAKECMDGOALS)

$(BINFILES):
	@mkdir -p $@
	$(MAKE) -C $@ SRC="$(SRC)/$@" OBJ="$(OBJ)/$@" \
		-f $(SRC)/$@/Makefile $(MAKECMDGOALS)

#
# List the dependencies to help out parallel builds.
dos extlinux linux mtools win32 win64: libinstaller
libinstaller: core
utils: mbr
core: com32
efi: core
gpxe: core

installer: installer-local
	set -e; for i in $(ISUBDIRS); \
		do $(MAKE) -C $$i SRC="$(SRC)/$$i" OBJ="$(OBJ)/$$i" \
		-f $(SRC)/$$i/Makefile all; done


installer-local: $(ITARGET) $(BINFILES)

strip: strip-local
	set -e; for i in $(ISUBDIRS); \
		do $(MAKE) -C $$i SRC="$(SRC)/$$i" OBJ="$(OBJ)/$$i" \
		-f $(SRC)/$$i/Makefile strip; done
	-ls -l $(BOBJECTS) $(IOBJECTS)

strip-local:

version.gen: $(topdir)/version $(topdir)/version.pl
	$(PERL) $(topdir)/version.pl $< $@ '%define < @'
version.h: $(topdir)/version $(topdir)/version.pl
	$(PERL) $(topdir)/version.pl $< $@ '#define < @'

local-install: installer
	mkdir -m 755 -p $(INSTALLROOT)$(BINDIR)
	install -m 755 -c $(INSTALL_BIN) $(INSTALLROOT)$(BINDIR)
	mkdir -m 755 -p $(INSTALLROOT)$(SBINDIR)
	install -m 755 -c $(INSTALL_SBIN) $(INSTALLROOT)$(SBINDIR)
	mkdir -m 755 -p $(INSTALLROOT)$(AUXDIR)
	install -m 644 -c $(INSTALL_AUX) $(INSTALLROOT)$(AUXDIR)
	-install -m 644 -c $(INSTALL_AUX_OPT) $(INSTALLROOT)$(AUXDIR)
	mkdir -m 755 -p $(INSTALLROOT)$(DIAGDIR)
	install -m 644 -c $(INSTALL_DIAG) $(INSTALLROOT)$(DIAGDIR)
	mkdir -m 755 -p $(INSTALLROOT)$(MANDIR)/man1
	install -m 644 -c $(topdir)/man/*.1 $(INSTALLROOT)$(MANDIR)/man1
	: mkdir -m 755 -p $(INSTALLROOT)$(MANDIR)/man8
	: install -m 644 -c man/*.8 $(INSTALLROOT)$(MANDIR)/man8

ifndef EFI_BUILD
install: local-install
	set -e ; for i in $(INSTALLSUBDIRS) ; \
		do $(MAKE) -C $$i SRC="$(SRC)/$$i" OBJ="$(OBJ)/$$i" \
		-f $(SRC)/$$i/Makefile $@; done
else
install:
	mkdir -m 755 -p $(INSTALLROOT)$(AUXDIR)/efi$(BITS)
	set -e ; for i in $(INSTALLSUBDIRS) ; \
		do $(MAKE) -C $$i SRC="$(SRC)/$$i" OBJ="$(OBJ)/$$i" \
		BITS="$(BITS)" AUXDIR="$(AUXDIR)/efi$(BITS)" \
		-f $(SRC)/$$i/Makefile $@; done
	-install -m 644 $(INSTALLABLE_MODULES) $(INSTALLROOT)$(AUXDIR)/efi$(BITS)
	install -m 644 com32/elflink/ldlinux/$(LDLINUX) $(INSTALLROOT)$(AUXDIR)/efi$(BITS)
endif

ifdef EFI_BUILD
netinstall:
	mkdir -p $(INSTALLROOT)$(TFTPBOOT)/efi$(BITS)
	install -m 644 $(NETINSTALLABLE) $(INSTALLROOT)$(TFTPBOOT)/efi$(BITS)
else
netinstall: installer
	mkdir -p $(INSTALLROOT)$(TFTPBOOT)
	install -m 644 $(NETINSTALLABLE) $(INSTALLROOT)$(TFTPBOOT)
endif

extbootinstall: installer
	mkdir -m 755 -p $(INSTALLROOT)$(EXTLINUXDIR)
	install -m 644 $(EXTBOOTINSTALL) $(INSTALLROOT)$(EXTLINUXDIR)

install-all: install netinstall extbootinstall

local-tidy:
	rm -f *.o *.elf *_bin.c stupid.* patch.offset
	rm -f *.lsr *.lst *.map *.sec *.tmp
	rm -f $(OBSOLETE)

tidy: local-tidy $(BESUBDIRS) $(IESUBDIRS) $(BSUBDIRS) $(ISUBDIRS)

local-clean:
	rm -f $(ITARGET)

clean: local-tidy local-clean $(BESUBDIRS) $(IESUBDIRS) $(BSUBDIRS) $(ISUBDIRS)

local-dist:
	find . \( -name '*~' -o -name '#*' -o -name core \
		-o -name '.*.d' -o -name .depend \) -type f -print0 \
	| xargs -0rt rm -f

dist: local-dist local-tidy $(BESUBDIRS) $(IESUBDIRS) $(BSUBDIRS) $(ISUBDIRS)

# Shortcut to build linux/syslinux using klibc
klibc:
	$(MAKE) clean
	$(MAKE) CC=klcc ITARGET= ISUBDIRS='linux extlinux' BSUBDIRS=
endif # ifeq ($(HAVE_FIRMWARE),)

endif # ifeq ($(topdir),)

local-spotless:
	find . \( -name '*~' -o -name '#*' -o -name core \
		-o -name '.*.d' -o -name .depend -o -name '*.so.*' \) \
		-type f -print0 \
	| xargs -0rt rm -f

spotless: local-spotless
	rm -rf $(all_firmware)

#
# Common rules that are needed by every invocation of make.
#
$(OBJDIR)/version.mk: $(topdir)/version $(topdir)/version.pl
	$(PERL) $(topdir)/version.pl $< $@ '< := @'
