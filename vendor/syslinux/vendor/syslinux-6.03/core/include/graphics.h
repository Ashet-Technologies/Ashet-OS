/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2012 Paulo Alcantara <pcacjr@zytor.com>
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
 * ----------------------------------------------------------------------- */

#ifndef GRAPHICS_H_
#define GRAPHICS_H_

#include <stddef.h>

#include "core.h"
#include "fs.h"

#ifdef IS_SYSLINUX
#define VGA_FILE_BUF_SIZE	(FILENAME_MAX + 2)
#else
#define VGA_FILE_BUF_SIZE	FILENAME_MAX
#endif

extern uint8_t UsingVGA;
extern uint16_t VGAPos;
extern uint16_t *VGAFilePtr;
extern char VGAFileBuf[VGA_FILE_BUF_SIZE];
extern char VGAFileMBuf[];
extern uint16_t VGAFontSize;

extern uint8_t UserFont;

extern char fontbuf[8192];

extern void vgadisplayfile(FILE *_fd);
extern void using_vga(uint8_t vga, uint16_t pix_cols, uint16_t pix_rows);

static inline void graphics_using_vga(uint8_t vga, uint16_t pix_cols,
                                      uint16_t pix_rows)
{
    using_vga(vga, pix_cols, pix_rows);
}

#endif /* GRAPHICS_H_ */
