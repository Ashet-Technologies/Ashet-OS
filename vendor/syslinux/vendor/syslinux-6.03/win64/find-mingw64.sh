#!/bin/sh

cc="$1"

for prefix in \
    mingw64- \
    x86_64-pc-mingw64- \
    x86_64-pc-mingw64msvc- \
    x86_64-pc-mingw32- \
    x86_64-pc-mingw32msvc- \
    x86_64-mingw64- \
    x86_64-mingw64msvc- \
    x86_64-mingw32- \
    x86_64-mingw32msvc- \
    x86_64-w64-mingw32- \
    x86_64-w64-mingw32msvc- \
    amd64-pc-mingw64- \
    amd64-pc-mingw64msvc- \
    amd64-pc-mingw32- \
    amd64-pc-mingw32msvc- \
    amd64-mingw64- \
    amd64-mingw64msvc- \
    amd64-mingw32- \
    amd64-mingw32msvc- \
    amd64-w64-mingw32- \
    amd64-w64-mingw32msvc- \
    ; do
    if "${prefix}${cc}" -v > /dev/null 2>&1; then
	echo "$prefix"
	exit 0
    fi
done

# No prefix, no idea what to do now...
echo missing-
exit 1
