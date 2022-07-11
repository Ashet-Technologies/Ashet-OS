#!/bin/bash

ROOT="$(realpath "$(dirname "$(realpath "$0")")"/../)"
export "PATH=/home/felix/projects/forks/binutils-gdb/prefix/bin/:${PATH}"

exec riscv32-none-eabi-gdb \
  "${ROOT}/zig-out/bin/ashet-os" \
  -ex "target remote localhost:1234"

