#!/bin/sh
set -e
clear
zig build \
    -Dhosted=false \
    -Dmachine=linux_pc \
    -freference-trace
exec ./zig-out/bin/debug-filter \
    --elf kernel=zig-out/kernel/linux_pc.elf \
    ./zig-out/kernel/linux_pc.elf \
        drive:zig-out/disk/linux_pc.img \
        video:vnc:800:480:0.0.0.0:5900