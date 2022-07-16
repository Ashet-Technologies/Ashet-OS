#!/bin/bash

ROOT="$(realpath "$(dirname "$(realpath "$0")")"/../)"

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
mmd -i "${DISK}" ::/etc
mmd -i "${DISK}" ::/docs

echo "populate root fs files"

unix2dos "${ROOT}/rootfs/etc/readme" 
unix2dos "${ROOT}/rootfs/docs/filesystem.txt" 

mcopy -i "${DISK}" "${ROOT}/rootfs/"* "::/"

for path in ${ROOT}/zig-out/apps/*.app; do 
  fname="$(basename "${path}")"
  app_name="${fname%.*}"
  
  echo "installing app: ${app_name}..."

  mmd -i "${DISK}" "::/apps/${app_name}"
  mcopy -i "${DISK}" "${path}" "::/apps/${app_name}/code"

  if [ -f "${ROOT}/zig-out/apps/${app_name}.icon" ]; then
    mcopy -i "${DISK}" "${ROOT}/zig-out/apps/${app_name}.icon" "::/apps/${app_name}/icon"
  fi
done

echo "showing root dir"

mdir -i "${DISK}" ::/

echo "done."