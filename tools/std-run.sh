#!/bin/sh

# env:
# - APP  (used for the debug filter instead of the OS)

set -e

ROOT="$(realpath "$(dirname "$(realpath "$0")")"/../)"

cd "${ROOT}"

if [ -z "$MACHINE" ]; then 
    MACHINE="rv32_virt"
fi

if [ -z "$APP" ]; then
    APP="${ROOT}/zig-out/kernel/${MACHINE}.elf"
fi

BOOTROM="${ROOT}/zig-out/rom/ashet-os.bin"
DISK="${ROOT}/zig-out/disk/${MACHINE}.img"





case $MACHINE in
    rv32_virt)
        qemu-system-riscv32 ${qemu_generic_flags} \
                
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

    bios_pc)
        qemu-system-i386 ${qemu_generic_flags} \
          
        | llvm-addr2line -e "${APP}"
        # | "${ROOT}/zig-out/bin/debug-filter" "${APP}"
        ;;
        
    efi_pc)
        qemu-system-x86_64 ${qemu_generic_flags} \
            -cpu qemu64 \
            -drive if=pflash,format=raw,unit=0,file=/usr/share/qemu/edk2-x86_64-code.fd,readonly=on \
            -drive if=ide,format=raw,unit=0,file="${DISK}" \
            -s "$@"
        ;;
        
    *)
        echo "Cannot start machine $MACHINE yet."
        exit 1
        ;;
esac

