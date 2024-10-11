#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// The functions replaced by this header are:
//
// mattrib -h -r -s ${target_file} 2>/dev/null # remove hidden bit, remove read-only bit, remove system bit
// mattrib -h -r -s s:/ldlinux.c32 2>/dev/null # remove hidden bit, remove read-only bit, remove system bit
// mattrib -h -r -s s:/ldlinux.sys 2>/dev/null # remove hidden bit, remove read-only bit, remove system bit
// mattrib +r +h +s ${target_file} # add hidden bit, add read-only bit, add system bit
// mattrib +r +h +s s:/${filename} # add hidden bit, add read-only bit, add system bit
// mattrib +r +h +s s:/ldlinux.c32 # add hidden bit, add read-only bit, add system bit
// mattrib +r +h +s s:/ldlinux.sys # add hidden bit, add read-only bit, add system bit
// mcopy -D o -D O -o - s:/ldlinux.c32 # copy file name from stdin into s:/ldlinux.c32
// mcopy -D o -D O -o - s:/ldlinux.sys # copy file name from stdin into s:/ldlinux.sys
// mmove -D o -D O s:/${filename} ${target_file} # move s:/${filename} to ${target_file}
//

bool mtools_configure(int fd, uint64_t offset);

//
// remove hidden bit, remove read-only bit, remove system bit
//
// ```
// mattrib -h -r -s ${disk_path}
// ```
//
bool mtools_flags_clear(char const * disk_path);

//
// add hidden bit, add read-only bit, add system bit
//
// ```
// mattrib +r +h +s ${disk_path}
// ```
//
bool mtools_flags_set(char const * disk_path);

// ```
// echo "${disk_data}" | mcopy -D o -D O -o - ${disk_path}
// ```
bool mtools_create_file(
    char const * disk_path,
    uint8_t const * disk_data1_ptr,
    size_t disk_data1_len,
    uint8_t const * disk_data2_ptr,
    size_t disk_data2_len);

// ```
// mmove -D o -D O s:/${disk_path_old} ${disk_path_new}
// ```
bool mtools_move_file(char const * disk_path_old, char const * disk_path_new);
