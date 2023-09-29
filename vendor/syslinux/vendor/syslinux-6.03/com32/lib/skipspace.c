#include <ctype.h>

char *skipspace(const char *p)
{
   while (isspace((unsigned char)*p))
            p++;
   return (char *)p;
}
