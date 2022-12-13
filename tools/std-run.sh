#!/bin/sh

# env:
# - ZARG (passed to `zig build)`
# - APP  (used for the debug filter instead of the OS)

set -e

ROOT="$(realpath "$(dirname "$(realpath "$0")")"/../)"

cd "${ROOT}"

if [ -z "$APP" ]; then
    APP="${ROOT}/zig-out/bin/ashet-os"
fi

if [ -z "$MACHINE" ]; then 
    MACHINE="rv32_virt"
fi

DISK="${ROOT}/zig-out/disk.img"

clear
zig build install -Dmachine=$MACHINE $ZARG
"${ROOT}/zig-out/bin/init-disk" "${DISK}"
echo "----------------------"

qemu_generic_flags="-d guest_errors,unimp -display gtk,show-tabs=on -serial stdio -no-reboot -no-shutdown"

case $MACHINE in
    rv32_virt)
        qemu-system-riscv32 ${qemu_generic_flags} \
                -M virt \
                -m 32M \
                -netdev user,id=hostnet \
                -object filter-dump,id=hostnet-dump,netdev=hostnet,file=ashet-os.pcap \
                -device virtio-gpu-device,xres=400,yres=300 \
                -device virtio-keyboard-device \
                -device virtio-mouse-device \
                -device virtio-net-device,netdev=hostnet,mac=52:54:00:12:34:56 \
                -bios none \
                -drive if=pflash,index=0,file=zig-out/bin/ashet-os.bin,format=raw \
                -drive if=pflash,index=1,file=zig-out/disk.img,format=raw \
                -s "$@" \
        | "${ROOT}/zig-out/bin/debug-filter" "${APP}"
        ;;
    microvm)
        qemu-system-i386 ${qemu_generic_flags} \
            -M microvm \
            -m 32M \
            -netdev user,id=hostnet \
            -object filter-dump,id=hostnet-dump,netdev=hostnet,file=ashet-os.pcap \
            -device virtio-gpu-device,xres=400,yres=300 \
            -device virtio-keyboard-device \
            -device virtio-mouse-device \
            -device virtio-net-device,netdev=hostnet,mac=52:54:00:12:34:56 \
            -s "$@" \
        | "${ROOT}/zig-out/bin/debug-filter" "${APP}"
        ;;
    generic_pc)
        mcopy -i "${DISK}" rootfs-x86/* ::
        mcopy -i "${DISK}" ./zig-out/bin/ashet-os ::/ashet-os

        syslinux --install "${DISK}"

        qemu-system-i386 ${qemu_generic_flags} \
          -machine pc \
          -cpu 486 \
          -hda "${DISK}" \
          -vga std \
          -s "$@"
         ;;
          # -device bochs-display,xres=800,yres=600 \
    *)
        echo "Cannot start machine $MACHINE yet."
        exit 1
        ;;
esac

# tcpdump -r ashet-os.pcap 
