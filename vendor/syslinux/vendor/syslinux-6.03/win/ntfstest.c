/* -------------------------------------------------------------------------- *
 *
 *   Copyright 2011 Shao Miller - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ------------------------------------------------------------------------- */

/****
 * ntfstest.c
 *
 * (C) Shao Miller, 2011
 *
 * Tests ntfssect.c functions
 *
 * With special thanks to Mark Roddy for his article:
 *   http://www.wd-3.com/archive/luserland.htm
 */
#include <windows.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ntfssect.h"

/*** Object types */

/*** Function declarations */
static void show_usage(void);
static void show_last_err(void);
static void show_err(DWORD);

/*** Struct/union definitions */

/*** Function definitions */

/** Program entry-point */
int main(int argc, char ** argv) {
    int rc;
    DWORD err;
    S_NTFSSECT_VOLINFO vol_info;
    HANDLE file;
    LARGE_INTEGER vcn, lba;
    S_NTFSSECT_EXTENT extent;
    LONGLONG len;
    BOOL ok;

    if (argc != 2) {
        rc = EXIT_FAILURE;
        show_usage();
        goto err_args;
      }

    /* Get volume info */
    err = NtfsSectGetVolumeInfoFromFileName(argv[1], &vol_info);
    if (err != ERROR_SUCCESS) {
        show_err(err);
        goto err_vol_info;
      }
    printf(
        "Volume has %d bytes per sector, %d sectors per cluster\n",
        vol_info.BytesPerSector,
        vol_info.SectorsPerCluster
      );

    /* Open the file for reading */
    file = CreateFile(
        argv[1],
        GENERIC_READ,
        FILE_SHARE_READ,
        NULL,
        OPEN_EXISTING,
        0,
        NULL
      );
    if (file == INVALID_HANDLE_VALUE) {
        rc = EXIT_FAILURE;
        show_last_err();
        goto err_file;
      }

    /* For each extent */
    for (
        vcn.QuadPart = 0;
        NtfsSectGetFileVcnExtent(file, &vcn, &extent) == ERROR_SUCCESS;
        vcn = extent.NextVcn
      ) {
        len = extent.NextVcn.QuadPart - extent.FirstVcn.QuadPart;
        printf("Extent @ VCN #%lld,", extent.FirstVcn.QuadPart);
        printf(" %lld clusters long:\n", len);
        printf("  VCN #%lld -", extent.FirstVcn.QuadPart);
        printf(" #%lld\n", extent.FirstVcn.QuadPart + len - 1);
        printf("  LCN #%lld -", extent.FirstLcn.QuadPart);
        printf(" #%lld\n", extent.FirstLcn.QuadPart + len - 1);
        err = NtfsSectLcnToLba(
            &vol_info,
            &extent.FirstLcn,
            &lba
          );
        if (err == ERROR_SUCCESS) {
            printf("  LBA #%lld -", lba.QuadPart);
            printf(
                " #%lld\n",
                lba.QuadPart + len * vol_info.SectorsPerCluster
              );
          }
        continue;
      }

    rc = EXIT_SUCCESS;

    CloseHandle(file);
    err_file:

    CloseHandle(vol_info.Handle);
    err_vol_info:

    err_args:

    return rc;
  }

/** Display usage */
static void show_usage(void) {
    static const char usage_text[] = "\
  File sector info . . . . . . . . . . . . . . . . . . . . Shao Miller, 2011\n\
\n\
  Usage: NTFSTEST.EXE <filename>\n\
\n\
  Attempts to dump cluster and sector info for <filename>.\n";

    printf(usage_text);
    return;
  }

static void show_last_err(void) {
    show_err(GetLastError());
    return;
  }

/** Display an error */
static void show_err(DWORD err_code) {
    void * buf;

    FormatMessage(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM,
        NULL,
        err_code,
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        (LPTSTR) &buf,
        0,
        NULL
      );
    fprintf(stderr, "Error: %s\n", buf);
    LocalFree(buf);
    return;
  }

