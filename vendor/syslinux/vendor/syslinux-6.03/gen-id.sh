#!/bin/sh
#
# Create a build ID for this build.  If we're using a git tree,
# generate an ID from "git describe", otherwise use the passed-in
# timestamp.
#
# Usage: gen-id.sh version timestamp
#

ver="$1"
tim="$2"
top=`dirname "$0"`

if test -n "$GIT_DIR" -o -d "$top"/.git -o -f "$top"/.git; then
    id="$(git describe)"
    if test -n "$id"; then
	if test x"$(echo "$id" | cut -d- -f1)" = xsyslinux; then
            id="$(echo "$id" | cut -d- -f2-)"
            if test x"$(echo "$id" | cut -d- -f1)" = x"$ver"; then
		id="$(echo "$id" | cut -d- -f2-)"
            fi
        fi
    fi
    if test -n "$id"; then
	if test -n "$(git diff-index --name-only HEAD)"; then
	    id="${id}"\*
	fi
    fi
fi
if test -z "$id"; then
  id="$tim"
fi
echo "$id"
