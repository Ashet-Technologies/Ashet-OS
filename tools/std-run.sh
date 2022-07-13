#!/bin/bash

ROOT="$(realpath "$(dirname "$(realpath "$0")")"/../)"

cd "${ROOT}"

clear \
   && zig build install \
   && "${ROOT}/tools/init-disk.sh" "${ROOT}/zig-out/disk.img" \
   && echo "----------------------" \
   && zig build run -- -serial stdio -s "$@"  2>/dev/null \
      | "${ROOT}/tools/addr2line.lua"
