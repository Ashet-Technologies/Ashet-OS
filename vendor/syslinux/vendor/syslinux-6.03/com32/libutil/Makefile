## -----------------------------------------------------------------------
##
##   Copyright 2001-2008 H. Peter Anvin - All Rights Reserved
##
##   Permission is hereby granted, free of charge, to any person
##   obtaining a copy of this software and associated documentation
##   files (the "Software"), to deal in the Software without
##   restriction, including without limitation the rights to use,
##   copy, modify, merge, publish, distribute, sublicense, and/or
##   sell copies of the Software, and to permit persons to whom
##   the Software is furnished to do so, subject to the following
##   conditions:
##
##   The above copyright notice and this permission notice shall
##   be included in all copies or substantial portions of the Software.
##
##   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
##   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
##   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
##   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
##   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
##   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
##   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
##   OTHER DEALINGS IN THE SOFTWARE.
##
## -----------------------------------------------------------------------

##
## Utility companion library for the COM32 library
##

VPATH = $(SRC)
include $(MAKEDIR)/elf.mk

LIBOBJS	   = ansiline.o ansiraw.o keyname.o \
	     sha1hash.o unbase64.o \
	     md5.o crypt-md5.o sha256crypt.o sha512crypt.o base64.o \
	     quicksort.o
LNXLIBOBJS = $(patsubst %.o,%.lo,$(LIBOBJS))

all: libutil.c32 libutil_lnx.a

libutil.elf: $(LIBOBJS)
	$(LD) $(LDFLAGS) -soname $(patsubst %.elf,%.c32,$(@F)) -o $@ $^

libutil_lnx.a: $(LNXLIBOBJS)
	rm -f $@
	$(AR) cq $@ $(LNXLIBOBJS)
	$(RANLIB) $@

tidy dist:
	rm -f *.o *.lo *.lst *.elf .*.d *.tmp

clean: tidy
	rm -f *.lnx libutil_lnx.a

spotless: clean
	rm -f *.lss *.a *.c32 *.com
	rm -f *~ \#*

install: all
	mkdir -m 755 -p $(INSTALLROOT)$(COM32DIR)
	install -m 644 libutil_lnx.a $(INSTALLROOT)$(COM32DIR)

-include .*.d
