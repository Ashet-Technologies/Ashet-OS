#!/bin/sh
set -e
clear
zig build \
    -Dmachine=linux_pc \
    -freference-trace

export LD_PRELOAD=/nix/store/4jz7xy4rpgb9drc756w7346h4gn83sv6-SDL2-2.30.1/lib/libSDL2-2.0.so.0.3000.1
exec ./zig-out/bin/debug-filter \
    --elf kernel=zig-out/kernel/linux_pc.elf \
    ./zig-out/kernel/linux_pc.elf \
        drive:zig-out/disk/linux_pc.img \
        video:sdl:800:480
        
               
#        video:vnc:800:480:0.0.0.0:5900
