## -----------------------------------------------------------------------
##   
##   Copyright 2008-2009 H. Peter Anvin - All Rights Reserved
##   Copyright 2009-2011 Intel Corporation; author: H. Peter Anvin
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
##   Boston MA 02110-1301, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

#
# Makefile for gpxe/gpxelinux.0
#
# Very simple, really...
#

VPATH = $(SRC)
TARGETS	= gpxelinux.0 gpxelinuxk.0

PXEMAKE = $(MAKE) -C $(SRC)/src NO_WERROR=1

all: $(TARGETS)

tidy:

clean: tidy

dist:
	$(MAKE) -C $(SRC)/src veryclean > /dev/null 2>&1

#spotless: clean dist
#Including 'dist' errors out for make ARCH=x86_64 spotless
spotless: clean
	rm -f $(TARGETS)

installer:

.NOTPARALLEL:

src/bin/blib.a:
	$(PXEMAKE) bin/blib.a

src/bin/undionly.kkpxe: src/bin/blib.a pxelinux.gpxe $(objdir)/core/pxelinux.0
	$(PXEMAKE) bin/undionly.kkpxe EMBEDDED_IMAGE=$(SRC)/pxelinux.gpxe,$(objdir)/core/pxelinux.0

gpxelinux.0: src/bin/undionly.kkpxe
	cp -f $(SRC)/$< $@

src/bin/undionly.kpxe: src/bin/blib.a pxelinuxk.gpxe $(objdir)/core/pxelinux.0
	$(PXEMAKE) bin/undionly.kpxe EMBEDDED_IMAGE=$(SRC)/pxelinuxk.gpxe,$(objdir)/core/pxelinux.0

gpxelinuxk.0: src/bin/undionly.kpxe
	cp -f $(SRC)/$< $@
