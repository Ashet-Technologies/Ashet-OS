# Build Refactoring to `build.zig` only

## Build Steps

1. Compile tools
2. Compile os
   - Kernel
   - Applications
3. Bundle rootfs
4. Create disk image
   - x86-pc-bios
     - 512MB disk image with MBR partition table, one partition
       - part 1: FAT32 root fs with x86 extras
     - syslinux installed
   - x86-pc-pxe
     - folder structure with root fs and pxe extras
     - syslinux installed
   - x86-pc-efi
     - 512MB disk image with GPT partition table, two partitions
       - part 1: ESP with kernel
       - part 2: FAT32 root fs
   - riscv-virt
     - 32 MB flat image without partitions
     - ADF root fs
   - arm-pi400-disk
     - ???
   - arm-pi400-pxe
     - ???
5. Start system
   - Launch QEMU with output filters applied
   - Launch dnsmasq with correct setup
   - ...
