#!/bin/sh

rootfs_path="$(realpath $(dirname $(realpath $0))/../rootfs)"

# validate wiki integrity
# for file in $(find "${rootfs_path}/wiki" -name "*.hdoc"); do 
#     # hyperdoc "$file" > /dev/null
#     ;
# done
