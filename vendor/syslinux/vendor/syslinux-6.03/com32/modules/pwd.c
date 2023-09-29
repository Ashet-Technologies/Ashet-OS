/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2010 Gene Cumm - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * Display present (current) working directory
 */

#include <errno.h>
#include <stdio.h>
#include <console.h>
#include <unistd.h>
#include <dirent.h>

/* Size of path buffer string */
#ifndef PATH_MAX
#  ifdef NAME_MAX
#    define PATH_MAX   NAME_MAX
#  elif FILENAME_MAX
#    define PATH_MAX   FILENAME_MAX
#  else
#    define PATH_MAX   256
#  endif       /* NAME_MAX */
#endif /* PATH_MAX */

int main(void)
{
    int rv = 0;
    char pwd[PATH_MAX], *pwdptr;

    pwdptr = getcwd(pwd, PATH_MAX);
    if (pwdptr) {
       if (pwd[0] != 0)
           puts(pwd);
       else
           puts(".");
    } else {
       rv = errno;
       puts("ERROR: getcwd() returned NULL");
    }
    return rv;
}
