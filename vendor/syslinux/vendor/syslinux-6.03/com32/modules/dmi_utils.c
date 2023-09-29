/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2006 Erwan Velu - All Rights Reserved
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

#include "stdio.h"
#include "dmi/dmi.h"

void display_bios_characteristics(s_dmi * dmi)
{
    int i;
    for (i = 0; i < BIOS_CHAR_NB_ELEMENTS; i++) {
	if (((bool *) (&dmi->bios.characteristics))[i] == true) {
	    moreprintf("\t\t%s\n", bios_charac_strings[i]);
	}
    }
    for (i = 0; i < BIOS_CHAR_X1_NB_ELEMENTS; i++) {
	if (((bool *) (&dmi->bios.characteristics_x1))[i] == true) {
	    moreprintf("\t\t%s\n", bios_charac_x1_strings[i]);
	}
    }

    for (i = 0; i < BIOS_CHAR_X2_NB_ELEMENTS; i++) {
	if (((bool *) (&dmi->bios.characteristics_x2))[i] == true) {
	    moreprintf("\t\t%s\n", bios_charac_x2_strings[i]);
	}
    }
}

void display_base_board_features(s_dmi * dmi)
{
    int i;
    for (i = 0; i < BASE_BOARD_NB_ELEMENTS; i++) {
	if (((bool *) (&dmi->base_board.features))[i] == true) {
	    moreprintf("\t\t%s\n", base_board_features_strings[i]);
	}
    }
}

void display_processor_flags(s_dmi * dmi)
{
    int i;
    for (i = 0; i < PROCESSOR_FLAGS_ELEMENTS; i++) {
	if (((bool *) (&dmi->processor.cpu_flags))[i] == true) {
	    moreprintf("\t\t%s\n", cpu_flags_strings[i]);
	}
    }
}
