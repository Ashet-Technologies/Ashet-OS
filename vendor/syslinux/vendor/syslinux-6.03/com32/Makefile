SUBDIRS = libupload tools lib elflink/ldlinux gpllib libutil modules mboot \
	  menu samples elflink rosh cmenu hdt gfxboot sysdump lua/src chain

.PHONY: subdirs $(SUBDIRS)
subdirs: $(SUBDIRS)
$(SUBDIRS):
	@mkdir -p $(OBJ)/$@
	$(MAKE) -C $(OBJ)/$@ SRC="$(SRC)"/$@ OBJ="$(OBJ)"/$@/ \
		-f $(SRC)/$@/Makefile $(MAKECMDGOALS)

all tidy dist clean spotless install: subdirs

# Parallel dependencies
chain mboot menu: lib libutil gpllib
cmenu: lib libutil
elflink/ldlinux: lib
gfxboot: lib libutil gpllib
hdt: lib libupload cmenu gpllib libutil
modules: lib libutil gpllib
rosh: lib libutil
samples: libutil elflink/ldlinux
sysdump: lib libutil libupload gpllib
lua/src: cmenu modules
