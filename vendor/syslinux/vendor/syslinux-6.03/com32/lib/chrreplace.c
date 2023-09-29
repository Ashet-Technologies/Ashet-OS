#include <ctype.h>

/* Replace char 'old' by char 'new' in source */
void chrreplace(char *source, char old, char new) 
{
    while (*source) { 
	source++;
	if (source[0] == old) source[0]=new;
    }
}

