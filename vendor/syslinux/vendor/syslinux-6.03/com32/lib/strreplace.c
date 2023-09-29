/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2011 Erwan Velu - All Rights Reserved
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * -----------------------------------------------------------------------
 */

#include <string.h>
#include <stdlib.h>

char *strreplace(const char *string, const char *string_to_replace,
		 const char *string_to_insert)
{
    char *token = NULL;
    char *out = NULL;

    size_t slen, srlen, silen;

    token = strstr(string, string_to_replace);
    if (!token)
	return strdup(string);

    slen  = strlen(string);
    srlen = strlen(string_to_replace);
    silen = strlen(string_to_insert);
    
    out = malloc(slen - srlen + silen + 1);
    if (!out)
	return NULL;
    
    memcpy(out, string, token - string);
    memcpy(out + (token - string), string_to_insert, silen);
    memcpy(out + (token - string) + silen, token + srlen, 
	   slen - srlen - (token - string) + 1);

    return out;
}
