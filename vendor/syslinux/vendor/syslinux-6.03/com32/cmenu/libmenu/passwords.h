#ifndef _PASSWORDS_H_
#define _PASSWORDS_H_

char authenticate_user(const char *username, const char *pwd);

char isallowed(const char *username, const char *perm);

// Initialise the list of of user passwords permissions from file
void init_passwords(const char *filename);
// Free all space used for internal data structures
void close_passwords(void);

#define MAX_USERS 128		// Maximum number of users
#define USERNAME_LENGTH 12	// Max length of user name
#define PWDHASH_LENGTH  40	// Max lenght of pwd hash

typedef struct {
    char username[USERNAME_LENGTH + 1];
    char pwdhash[PWDHASH_LENGTH + 1];
    char *perms;		// pointer to string containing ":" delimited permissions
} pwdentry;

typedef pwdentry *p_pwdentry;

#define GUEST_USER "guest"

#endif
