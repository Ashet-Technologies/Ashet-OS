#!/usr/bin/env bash

ROOT="$(realpath "$(dirname "$(realpath "$0")")"/../)"
export "PATH=/home/felix/projects/forks/binutils-gdb/prefix/bin/:${PATH}"

case $MACHINE in
    rv32_virt)
      exec riscv32-none-eabi-gdb \
        "${ROOT}/zig-out/bin/ashet-os" \
        -ex "target remote localhost:1234"
      ;;
    microvm)
      exec gdb \
        "${ROOT}/zig-out/bin/ashet-os" \
        -ex "target remote localhost:1234"
      ;;
    generic_pc)
      exec gdb \
        "${ROOT}/zig-out/bin/ashet-os" \
        -ex "target remote localhost:1234"
      ;;
    *)
      echo "unsupported debugging platform for machine $MACHINE"
      exit 1
      ;; 
esac