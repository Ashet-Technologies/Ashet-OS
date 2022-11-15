#!/bin/bash

set -e

ROOT="$(realpath "$(dirname "$(realpath "$0")")"/../)"

cd "${ROOT}"

clear
zig build install
"${ROOT}/tools/init-disk.sh" "${ROOT}/zig-out/disk.img"
echo "----------------------"
qemu-system-riscv32 \
        -display gtk,show-tabs=on\
        -M virt \
        -m 32M \
        -device virtio-gpu-device,xres=400,yres=300 \
        -device virtio-keyboard-device \
        -device virtio-mouse-device \
        -d guest_errors,int \
        -bios none \
        -drive if=pflash,index=0,file=zig-out/bin/ashet-os.bin,format=raw \
        -drive if=pflash,index=1,file=zig-out/disk.img,format=raw \
        -serial stdio \
        -s "$@" \
| "${ROOT}/tools/addr2line.lua"
