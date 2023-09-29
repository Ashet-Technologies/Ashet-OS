## -----------------------------------------------------------------------
##
##   Copyright 2012 Gene Cumm
##
##   Some logic from win32/Makefile:
##     Copyright 1998-2008 H. Peter Anvin - All Rights Reserved
##     Copyright 2010 Intel Corporation; author: H. Peter Anvin
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
##   Boston MA 02111-1307, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

##
## AsciiDoc documentation for syslinux
##

topdir = ..
MAKEDIR = $(topdir)/mk
# include $(MAKEDIR)/embedded.mk

VPATH = $(SRC)

A2X_OPTS	 = -k
# A2X_OPTS	+= -v
A2X_MAN_OPTS	 = -D man -f manpage

DOCS 		 = syslinux.txt syslinux-cli.txt syslinux.cfg.txt \
		   isolinux.txt pxelinux.txt
MAN_DOCS	 = man/syslinux.1 man/syslinux-cli.1 man/syslinux.cfg.5 \
		   man/isolinux.1 man/pxelinux.1
HTML_DOCS	:= $(patsubst %.txt,html/%.html,$(DOCS)) 
XHTML_DOCS	:= $(patsubst %.txt,%.html,$(DOCS))
# MAN_DOCS	:= $(patsubst %.txt,man/%.1,$(DOCS1)) $(patsubst %.txt,man/%.5,$(DOCS5))
TEXT_DOCS	:= $(patsubst %.txt,%.text,$(DOCS))
PDF_DOCS	:= $(patsubst %.txt,%.pdf,$(DOCS))
TARGETS		 =

# ASCIIDOC_OK := $(shell which asciidoc 2>&1 ; echo $$?)
ASCIIDOC_OK	:= $(shell which asciidoc > /dev/null ; echo $$?)
A2X_XML_OK	:= $(shell a2x $(A2X_OPTS) -f docbook hello.txt 2>&1 ; echo $$?)
ifeq ($(A2X_XML_OK),0)
A2X_MAN_OK	:= $(shell [ ! -d man ] && mkdir man ; a2x $(A2X_MAN_OPTS) hello.txt 2>&1 ; echo $$?)
A2X_XHTML_OK	:= $(shell a2x $(A2X_OPTS) -f xhtml hello.xml 2>&1 ; echo $$?)
A2X_TEXT_OK	:= $(shell a2x $(A2X_OPTS) -f text hello.xml 2>&1 ; echo $$?)
endif

ifeq ($(ASCIIDOC_OK),0)
TARGETS		+= $(HTML_DOCS)
endif
ifeq ($(A2X_MAN_OK),0)
TARGETS		+= $(MAN_DOCS)
endif
ifeq ($(A2X_XHTML_OK),0)
TARGETS		+= $(XHTML_DOCS)
endif
ifeq ($(A2X_TEXT_OK),0)
TARGETS		+= $(TEXT_DOCS)
endif

# $(HTML_DOCS) $(MAN_DOCS) $(XHTML_DOCS) $(TEXT_DOCS)
all:	$(TARGETS)

syslinux.cfg.txt:	com-bug.txt com-rpt.txt

# During 'make all', *.xml is kept but deleted at the end; do we _really_
#	need the XML longer?
.PRECIOUS:	%.xml

# %.html:	%.txt
# 	asciidoc -D html $<

# Mark as .PHONY so they're ignored if found in VPATH
.PHONY: html/ man/ text/ xhtml/

html/ man/ text/ xhtml/:
	mkdir -p $@

html/%.html:	%.txt	| html/
	asciidoc -o $@ $<

# As of AsciiDoc-8.5.2, altering the output filename for a2x does not appear possible
# xhtml/%.html:	%.txt
# 	a2x $(A2X_OPTS) -D xhtml -f xhtml $<
# text/%.text:	%.xml %.txt
# 	a2x $(A2X_OPTS) -D text -f text $<

%.xml:	%.txt
	a2x $(A2X_OPTS) -f docbook $<

# when %.xml is missing, an update to %.txt must force regeneration
%.html:	%.xml %.txt
	a2x $(A2X_OPTS) -f xhtml $<

man/%.1:	%.txt	| man/
	a2x $(A2X_MAN_OPTS) $<

man/%.5:	%.txt	| man/
	a2x $(A2X_MAN_OPTS) $<

%.text:	%.xml %.txt
	a2x $(A2X_OPTS) -f text $<

%.pdf:	%.xml %.txt
	a2x $(A2X_OPTS) -f pdf $<

tidy dist:
	rm -f *~ *.xml *.text.html text/*.text.html text/*.xml xhtml/*.xml

clean: tidy

spotless: clean
	rm -f *.1 *.5 *.css *.html *.text html/*.html man/*.1 man/*.5 text/*.text xhtml/*.html xhtml/*.css

-include .*.d
