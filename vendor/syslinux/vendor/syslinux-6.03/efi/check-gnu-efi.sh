#!/bin/sh

# Verify that gnu-efi is installed in the object directory for our
# firmware. If it isn't, build it.

if [ $# -lt 2 ]; then
cat <<EOF
Usage: $0: <arch> <objdir>

Check for gnu-efi libraries and header files in <objdir> and, if none
exist, build and install them.

  <arch>   - A gnu-efi \$ARCH argument, i.e. ia32, x86_64
  <objdir> - The Syslinux object directory

EOF
    exit 1
fi

ARCH=$1
objdir=$2

if [ ! \( -f "$objdir/include/efi/$ARCH/efibind.h" -a -f "$objdir/lib/libefi.a" -a -f "$objdir/lib/libgnuefi.a" \) ]; then
    # Build the external project with a clean make environment, as
    # Syslinux disables built-in implicit rules.
    export MAKEFLAGS=

    ../../efi/build-gnu-efi.sh $ARCH "$objdir" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
	printf "Failed to build gnu-efi. "
	printf "Execute the following command for full details: \n\n"
	printf "build-gnu-efi.sh $ARCH $objdir\n\n"

	exit 1
    fi
else
    printf "skip gnu-efi build/install\n"
fi
