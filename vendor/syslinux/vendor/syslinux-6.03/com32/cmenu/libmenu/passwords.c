/* -*- c -*- ------------------------------------------------------------- *
 *
 *   Copyright 2004-2005 Murali Krishnan Ganapathy - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Bostom MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

#include "passwords.h"
#include "des.h"
#include "string.h"
#include <stdlib.h>
#include <stdio.h>
#include "tui.h"

#define MAX_LINE 512
// Max line length in a pwdfile
p_pwdentry userdb[MAX_USERS];	// Array of pointers
int numusers;			// Actual number of users

// returns true or false, i.e. 1 or 0
char authenticate_user(const char *username, const char *pwd)
{
    char salt[12];
    int i;

    for (i = 0; i < numusers; i++) {
	if (userdb[i] == NULL)
	    continue;
	if (strcmp(username, userdb[i]->username) == 0) {
	    strcpy(salt, userdb[i]->pwdhash);
	    salt[2] = '\0';
	    if (strcmp(userdb[i]->pwdhash, crypt(pwd, salt)) == 0)
		return 1;
	}
    }
    return 0;
}

// Does user USERNAME  have permission PERM
char isallowed(const char *username, const char *perm)
{
    int i;
    char *dperm;
    char *tmp;

    // If no users, then everybody is allowed to do everything
    if (numusers == 0)
	return 1;
    if (strcmp(username, GUEST_USER) == 0)
	return 0;
    dperm = (char *)malloc(strlen(perm) + 3);
    strcpy(dperm + 1, perm);
    dperm[0] = ':';
    dperm[strlen(perm) + 1] = ':';
    dperm[strlen(perm) + 2] = 0;
    // Now dperm = ":perm:"
    for (i = 0; i < numusers; i++) {
	if (strcmp(userdb[i]->username, username) == 0)	// Found the user
	{
	    if (userdb[i]->perms == NULL)
		return 0;	// No permission
	    tmp = strstr(userdb[i]->perms, dperm);	// Search for permission
	    free(dperm);	// Release memory
	    if (tmp == NULL)
		return 0;
	    else
		return 1;
	}
    }
    // User not found return 0
    free(dperm);
    return 0;
}

// Initialise the list of of user passwords permissions from file
void init_passwords(const char *filename)
{
    int i;
    char line[MAX_LINE], *p, *user, *pwdhash, *perms;
    FILE *f;

    for (i = 0; i < MAX_USERS; i++)
	userdb[i] = NULL;
    numusers = 0;

    if (!filename)
	return;			// No filename specified

    f = fopen(filename, "r");
    if (!f)
	return;			// File does not exist

    // Process each line
    while (fgets(line, sizeof line, f)) {
	// Replace EOLN with \0
	p = strchr(line, '\r');
	if (p)
	    *p = '\0';
	p = strchr(line, '\n');
	if (p)
	    *p = '\0';

	// If comment line or empty ignore line
	p = line;
	while (*p == ' ')
	    p++;		// skip initial spaces
	if ((*p == '#') || (*p == '\0'))
	    continue;		// Skip comment lines

	user = p;		// This is where username starts
	p = strchr(user, ':');
	if (p == NULL)
	    continue;		// Malformed line skip
	*p = '\0';
	pwdhash = p + 1;
	if (*pwdhash == 0)
	    continue;		// Malformed line (no password specified)
	p = strchr(pwdhash, ':');
	if (p == NULL) {	// No perms specified
	    perms = NULL;
	} else {
	    *p = '\0';
	    perms = p + 1;
	    if (*perms == 0)
		perms = NULL;
	}
	// At this point we have user,pwdhash and perms setup
	userdb[numusers] = (p_pwdentry) malloc(sizeof(pwdentry));
	strcpy(userdb[numusers]->username, user);
	strcpy(userdb[numusers]->pwdhash, pwdhash);
	if (perms == NULL)
	    userdb[numusers]->perms = NULL;
	else {
	    userdb[numusers]->perms = (char *)malloc(strlen(perms) + 3);
	    (userdb[numusers]->perms)[0] = ':';
	    strcpy(userdb[numusers]->perms + 1, perms);
	    (userdb[numusers]->perms)[strlen(perms) + 1] = ':';
	    (userdb[numusers]->perms)[strlen(perms) + 2] = 0;
	    // Now perms field points to ":perms:"
	}
	numusers++;
    }
    fclose(f);
}

void close_passwords(void)
{
    int i;

    for (i = 0; i < numusers; i++)
	if (userdb[i] != NULL)
	    free(userdb[i]);
    numusers = 0;
}
