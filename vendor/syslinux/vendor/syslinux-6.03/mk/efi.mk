include $(MAKEDIR)/syslinux.mk

com32 = $(topdir)/com32
core = $(topdir)/core

# Support IA32 and x86_64 platforms with one build
# Set up architecture specifics; for cross compilation, set ARCH as apt
# gnuefi sets up architecture specifics in ia32 or x86_64 sub directories
# set up the LIBDIR and EFIINC for building for the appropriate architecture
GCCOPT := $(call gcc_ok,-fno-stack-protector,)
EFIINC = $(objdir)/include/efi
LIBDIR  = $(objdir)/lib

ifeq ($(ARCH),i386)
	ARCHOPT = -m32 -march=i386
	EFI_SUBARCH = ia32
endif
ifeq ($(ARCH),x86_64)
	ARCHOPT = -m64 -march=x86-64
	EFI_SUBARCH = $(ARCH)
endif

#LIBDIR=/usr/lib
FORMAT=efi-app-$(EFI_SUBARCH)

CFLAGS = -I$(EFIINC) -I$(EFIINC)/$(EFI_SUBARCH) \
		-DEFI_FUNCTION_WRAPPER -fPIC -fshort-wchar -ffreestanding \
		-Wall -I$(com32)/include -I$(com32)/include/sys \
		-I$(core)/include -I$(core)/ $(ARCHOPT) \
		-I$(com32)/lib/ -I$(com32)/libutil/include -std=gnu99 \
		-DELF_DEBUG -DSYSLINUX_EFI -I$(objdir) \
		$(GCCWARN) -D__COM32__ -D__FIRMWARE_$(FIRMWARE)__ -mno-red-zone \
		-DLDLINUX=\"$(LDLINUX)\" -fvisibility=hidden \
		-Wno-unused-parameter $(GCCOPT)

CRT0 := $(LIBDIR)/crt0-efi-$(EFI_SUBARCH).o
LDSCRIPT := $(LIBDIR)/elf_$(EFI_SUBARCH)_efi.lds

LDFLAGS = -T $(SRC)/$(ARCH)/syslinux.ld -Bsymbolic -pie -nostdlib -znocombreloc \
		-L$(LIBDIR) --hash-style=gnu -m elf_$(ARCH) $(CRT0) -E

SFLAGS     = $(GCCOPT) $(GCCWARN) $(ARCHOPT) \
	     -fomit-frame-pointer -D__COM32__ -D__FIRMWARE_$(FIRMWARE)__ \
	     -nostdinc -iwithprefix include \
	     -I$(com32)/libutil/include -I$(com32)/include -I$(com32)/include/sys $(GPLINCLUDE)

LIBEFI = $(objdir)/lib/libefi.a

$(LIBEFI):
	@echo Building gnu-efi for $(EFI_SUBARCH)
	$(topdir)/efi/check-gnu-efi.sh $(EFI_SUBARCH) $(objdir)

%.o: %.S	# Cancel old rule

%.o: %.c

.PRECIOUS: %.o
%.o: %.S $(LIBEFI)
	$(CC) $(SFLAGS) -c -o $@ $<

.PRECIOUS: %.o
%.o: %.c $(LIBEFI)
	$(CC) $(CFLAGS) -c -o $@ $<

#%.efi: %.so
#	$(OBJCOPY) -j .text -j .sdata -j .data -j .dynamic -j .dynsym -j .rel \
#		-j .rela -j .reloc --target=$(FORMAT) $*.so $@
