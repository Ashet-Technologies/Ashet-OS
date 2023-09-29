#!/bin/sh

cc="$1"

for prefix in \
    mingw- \
    mingw32- \
    i386-pc-mingw32- \
    i486-pc-mingw32- \
    i586-pc-mingw32- \
    i686-pc-mingw32- \
    i386-pc-mingw32msvc- \
    i486-pc-mingw32msvc- \
    i586-pc-mingw32msvc- \
    i686-pc-mingw32msvc- \
    i386-mingw32- \
    i486-mingw32- \
    i586-mingw32- \
    i686-mingw32- \
    i386-mingw32msvc- \
    i486-mingw32msvc- \
    i586-mingw32msvc- \
    i686-mingw32msvc- \
    i686-w64-mingw32-; do
    if "${prefix}${cc}" -v > /dev/null 2>&1; then
	echo "$prefix"
	exit 0
    fi
done

# No prefix, no idea what to do now...
echo missing-
exit 1
