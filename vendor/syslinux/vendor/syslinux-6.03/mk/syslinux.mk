## -*- makefile -*- -------------------------------------------------------
##   
##   Copyright 2008 H. Peter Anvin - All Rights Reserved
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
##   Boston MA 02110-1301, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

##
## Common configurables
##

# No builtin rules
MAKEFLAGS += -r
MAKE      += -r

BINDIR   = /usr/bin
SBINDIR  = /sbin
LIBDIR   = /usr/lib
DATADIR  = /usr/share
AUXDIR   = $(DATADIR)/syslinux
DIAGDIR  = $(AUXDIR)/diag
MANDIR	 = /usr/man
INCDIR   = /usr/include
TFTPBOOT = /tftpboot
COM32DIR = $(AUXDIR)/com32

BOOTDIR	    = /boot
EXTLINUXDIR = $(BOOTDIR)/extlinux

ifdef DEBUG
# This allows DEBUGOPT to be set from the command line
DEBUGOPT = -DDEBUG=$(DEBUG)
endif

NASM	 = nasm
NASMOPT  = -Ox $(DEBUGOPT)

PERL	 = perl
PYTHON	 = python
UPX	 = upx

CHMOD	 = chmod

CC	 = gcc
gcc_ok   = $(shell tmpf=gcc_ok.$$$$.tmp; \
		   if $(CC) $(GCCOPT) $(1) -c $(topdir)/dummy.c \
			-o $$tmpf 2>/dev/null ; \
		   then echo '$(1)'; else echo '$(2)'; fi; \
		   rm -f $$tmpf)

LD	 = ld
OBJDUMP	 = objdump
OBJCOPY  = objcopy
STRIP    = strip
AR       = ar
NM       = nm
RANLIB   = ranlib
STRIP	 = strip
GZIPPROG = gzip
XZ	 = xz
PNGTOPNM = pngtopnm
MCOPY    = mcopy
MFORMAT  = mformat
MKISOFS  = mkisofs
SED	 = sed
WGET	 = wget

com32    = $(topdir)/com32

# Architecture definition
SUBARCH := $(shell uname -m | sed -e s/i.86/i386/) 
# on x86_64, ARCH has trailing whitespace
# strip white spaces in ARCH
ARCH ?= $(strip $(SUBARCH))

# Common warnings we want for all gcc-generated code
GCCWARN  = -W -Wall -Wstrict-prototypes $(DEBUGOPT)

# Common stanza to make gcc generate .*.d dependency files
MAKEDEPS = -Wp,-MT,$@,-MD,$(dir $@).$(notdir $@).d

# Dependencies that exclude system headers; use whenever we use
# header files from the platform.
UMAKEDEPS = -Wp,-MT,$@,-MMD,$(dir $@).$(notdir $@).d

# Items that are only appropriate during development; this file is
# removed when tarballs are generated.
-include $(MAKEDIR)/devel.mk

# Local additions, like -DDEBUG can go here
-include $(MAKEDIR)/local.mk
