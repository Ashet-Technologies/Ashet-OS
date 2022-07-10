#!/bin/bash

set -e

DISK="$1"
SIZE=32M

if [ -z "${DISK}" ]; then 
  echo "usage: init-disk.sh <disk file>" 1>&2
  exit 1
fi

echo "allocate storage..."
fallocate -l "${SIZE}" "${DISK}"

echo "formatting..."
mformat -i zig-out/disk.img -v ASHET -M 512

echo "create directory structure..."

mmd -i "${DISK}" ::/bin
mmd -i "${DISK}" ::/apps


echo "installing app: shell..."

mmd -i "${DISK}" ::/apps/shell
mcopy -i "${DISK}" zig-out/bin/shell.bin ::/apps/shell/code

echo "showing root dir"

mdir -i "${DISK}" ::/apps/shell

echo "done."