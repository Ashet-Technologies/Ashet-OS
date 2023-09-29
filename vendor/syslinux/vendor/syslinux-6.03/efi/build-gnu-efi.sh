#!/bin/sh

set -e

# Initialise the gnu-efi submodule and ensure the source is up-to-date.
# Then build and install it for the given architecture.

if [ $# -lt 2 ]; then
cat <<EOF
Usage: $0: <arch> <objdir>

Build the <arch> gnu-efi libs and header files and install in <objdir>.

  <arch>   - A gnu-efi \$ARCH argument, i.e. ia32, x86_64
  <objdir> - The Syslinux object directory

EOF
    exit 1
fi

ARCH="$1"
objdir="$(readlink -f $2)"

if [ ! -e ../version.h ]; then
    printf "build-gnu-efi.sh: Cannot be run outside Syslinux object tree\n"
    pwd
    exit 1
fi

(
	cd ../..
	git submodule update --init
)

mkdir -p "$objdir/gnu-efi"
cd "$objdir/gnu-efi"

EFIDIR="$(readlink -f "$objdir/../gnu-efi/gnu-efi-3.0")"

make SRCDIR="$EFIDIR" TOPDIR="$EFIDIR" -f "$EFIDIR/Makefile" ARCH=$ARCH
make SRCDIR="$EFIDIR" TOPDIR="$EFIDIR" -f "$EFIDIR/Makefile" ARCH=$ARCH PREFIX="$objdir" install

cd "$objdir/efi"
