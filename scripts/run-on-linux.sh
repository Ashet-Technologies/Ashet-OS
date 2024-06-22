#!/bin/sh
set -e
clear


lpaths="$(pkg-config --libs-only-L sdl2 | sed -re 's/-L//g')"
libs="$(pkg-config --libs-only-l sdl2 | sed -re 's/-l([^ ]+)/lib\1.so/g')"

for path_prefix in ${lpaths}; do
    for path_suffix in ${libs}; do
        lpath="${path_prefix}/${path_suffix}"
        if [ -e "${lpath}" ]; then
            if [ -z "${LD_PRELOAD}" ]; then
                LD_PRELOAD="${lpath}"
            else
                LD_PRELOAD="${lpath}:${LD_PRELOAD}"
            fi
        fi

    done
done

# zig build \
#     -Dmachine=linux_pc \
#     -freference-trace \
#     "$@"

# readelf -ldrS --syms --dyn-syms  zig-out/apps/hosted/hello-world.app  > /tmp/dump
# objdump -S  zig-out/apps/hosted/hello-world.app  >> /tmp/dump


export LD_PRELOAD

if [ -z "$GDB" ]; then
    exec ./zig-out/bin/debug-filter \
        --elf kernel=zig-out/kernel/linux_pc.elf \
        ./zig-out/kernel/linux_pc.elf \
            drive:zig-out/disk/linux_pc.img \
            video:sdl:800:480
else
    exec gdb ./zig-out/kernel/linux_pc.elf -ex 'r drive:zig-out/disk/linux_pc.img video:sdl:800:480'
fi
               
#        video:vnc:800:480:0.0.0.0:5900
