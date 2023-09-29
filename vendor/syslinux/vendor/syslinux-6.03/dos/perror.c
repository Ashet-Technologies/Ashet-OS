#include <stdio.h>
#include <errno.h>

void perror(const char *msg)
{
    printf("%s: error %s\n", msg, errno);
}
