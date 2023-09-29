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

#include "hdt-common.h"
#include "hdt-dump.h"
#include <syslinux/config.h>

void dump_hdt(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {

	(void) hardware;
	CREATE_NEW_OBJECT;
	add_s("hdt.product_name",PRODUCT_NAME);
	add_s("hdt.version",VERSION);
	add_s("hdt.code_name",CODENAME);
	add_s("hdt.author", AUTHOR);
	add_s("hdt.core_developer", CORE_DEVELOPER);
	char *contributors[NB_CONTRIBUTORS] = CONTRIBUTORS;
	for (int c = 0; c < NB_CONTRIBUTORS; c++) {
		add_s("hdt.contributor", contributors[c]);
	}
	add_s("hdt.website",WEBSITE_URL);
	add_s("hdt.irc_channel",IRC_CHANNEL);
	FLUSH_OBJECT
	to_cpio("hdt");
}
