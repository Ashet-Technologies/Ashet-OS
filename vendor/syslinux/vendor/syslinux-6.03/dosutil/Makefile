#
# OpenWatcom compile and link utility
#
VPATH = $(SRC)
include $(MAKEDIR)/syslinux.mk

WCL	= wcl
WCLOPT	= -6 -osx -mt -bt=DOS -l=COM

WCL_IS_GOOD := $(shell $(WCL) $(WCLOPT) \
        -o hello.exe $(SRC)/../win/hello.c >/dev/null 2>&1 ; echo $$?)

UPX     = upx

NASM    = nasm
NASMOPT = -Ox

WCTARGETS = mdiskchk.com
NSTARGETS = eltorito.sys copybs.com
WCOBJS    = $(addprefix $(SRC)/,$(WCTARGETS))
NSOBJS    = $(addprefix $(OBJ)/,$(NSTARGETS))
TARGETS   = $(WCTARGETS) $(NSTARGETS)

%.obj: %.c
	$(WCL) $(WCLOPT) -c -fo=$@ $<

%.com: %.obj
	$(WCL) $(WCLOPT) -fe=$@ $<
	$(UPX) --ultra-brute --lzma $@ || \
		$(UPX) --ultra-brute $@ || \
		true
	rm -f $*.0*
	chmod a-x $@

%.sys: %.asm
	$(NASM) $(NASMOPT) -f bin -o $@ -l $*.lst $<
	$(UPX) --ultra-brute --lzma $@ || \
		$(UPX) --ultra-brute $@ || \
		true
	rm -f $*.0*
	chmod a-x $@

%.com: %.asm
	$(NASM) $(NASMOPT) -f bin -o $@ -l $*.lst $<
	$(UPX) --ultra-brute --lzma $@ || \
		$(UPX) --ultra-brute $@ || \
		true
	rm -f $*.0*
	chmod a-x $@

ifeq ($(WCL_IS_GOOD),0)
all: $(TARGETS)
else
all: $(NSTARGETS)
	rm -f $(WCTARGETS)
endif

tidy dist:
	-rm -f *.obj *.lst *.o *.0*

clean: tidy

spotless: clean
	-rm -f $(NSTARGETS) *~

installer: all

install: installer
	mkdir -m 755 -p $(INSTALLROOT)$(AUXDIR)/dosutil
	install -m 644 $(WCOBJS) $(INSTALLROOT)$(AUXDIR)/dosutil
	install -m 644 $(NSOBJS) $(INSTALLROOT)$(AUXDIR)/dosutil
