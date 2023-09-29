/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Pierre-Alexandre Meyer - All Rights Reserved
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

#include <stdio.h>
#include <string.h>

/* Computing div(x,y) */
#define sub(val) (((val%1024)*100)>>10)
#define sub_dec(val) (((val%1000)*100)/1000)

void sectors_to_size(int sectors, char *buffer)
{
    int b = (sectors / 2);
    int mib = b >> 10;
    int gib = mib >> 10;
    int tib = gib >> 10;

    if (tib > 0)
	sprintf(buffer, "%3d.%02d TiB", tib,sub(gib));
    else if (gib > 0)
	sprintf(buffer, "%3d.%02d GiB", gib,sub(mib));
    else if (mib > 0)
	sprintf(buffer, "%3d.%02d MiB", mib,sub(b));
    else
	sprintf(buffer, "%d B", b);
}

void sectors_to_size_dec(char *previous_unit, int *previous_size, char *unit,
			 int *size, int sectors)
{
    *size = sectors / 2;	// Converting to bytes
    strlcpy(unit, "KB", 2);
    strlcpy(previous_unit, unit, 2);
    *previous_size = *size;
    if (*size > 1000) {
	*size = *size / 1000;
	strlcpy(unit, "MB", 2);
	if (*size > 1000) {
	    *previous_size = *size;
	    *size = *size / 1000;
	    strlcpy(previous_unit, unit, 2);
	    strlcpy(unit, "GB", 2);
	    if (*size > 1000) {
		*previous_size = *size;
		*size = *size / 1000;
		strlcpy(previous_unit, unit, 2);
		strlcpy(unit, "TB", 2);
	    }
	}
    }
}

/* Return the human readable size of device
 * This function avoid disk's size rounding while
 * not using float as they aren't currently supported */
void sectors_to_size_dec2(int sectors, char *buffer)
{
    int b = (sectors / 2);
    int mib = b / 1000;
    int gib = mib / 1000;
    int tib = gib / 1000;

    if (tib > 0)
	sprintf(buffer, "%3d.%02d TB", tib,sub_dec(gib));
    else if (gib > 0)
	sprintf(buffer, "%3d.%02d GB", gib,sub_dec(mib));
    else if (mib > 0)
	sprintf(buffer, "%3d.%02d MB", mib,sub_dec(b));
    else
	sprintf(buffer, "%d B", b);
}
