/*
 * Small jpeg decoder library
 *
 * Copyright (c) 2006, Luc Saillard <luc@saillard.org>
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice,
 *  this list of conditions and the following disclaimer.
 *
 * - Redistributions in binary form must reproduce the above copyright notice,
 *  this list of conditions and the following disclaimer in the documentation
 *  and/or other materials provided with the distribution.
 *
 * - Neither the name of the author nor the names of its contributors may be
 *  used to endorse or promote products derived from this software without
 *  specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "tinyjpeg.h"
#include "tinyjpeg-internal.h"

/**
 *  YCrCb -> Grey (1x1, 1x2)
 *  .---.
 *  | 1 |
 *  `---'
 */
static void YCrCB_to_Grey_1xN(struct jdec_private *priv, int sx, int sy)
{
  const unsigned char *y;
  unsigned char *p;
  unsigned int i;
  int offset_to_next_row;

  p = priv->plane[0];
  y = priv->Y;
  offset_to_next_row = priv->bytes_per_row[0];

  for (i = sy; i > 0; i--) {
     memcpy(p, y, sx);
     y += 8;
     p += offset_to_next_row;
  }
}

/**
 *  YCrCb -> Grey (2x1, 2x2)
 *  .-------.
 *  | 1 | 2 |
 *  `-------'
 */
static void YCrCB_to_Grey_2xN(struct jdec_private *priv, int sx, int sy)
{
  const unsigned char *y;
  unsigned char *p;
  unsigned int i;
  int offset_to_next_row;

  p = priv->plane[0];
  y = priv->Y;
  offset_to_next_row = priv->bytes_per_row[0];

  for (i = sy; i > 0; i--) {
     memcpy(p, y, sx);
     y += 16;
     p += offset_to_next_row;
  }
}

static int initialize_grey(struct jdec_private *priv,
			   unsigned int *bytes_per_blocklines,
			   unsigned int *bytes_per_mcu)
{
  if (!priv->bytes_per_row[0])
    priv->bytes_per_row[0] = priv->width;
  if (!priv->components[0])
    priv->components[0] = malloc(priv->height * priv->bytes_per_row[0]);

  bytes_per_blocklines[0] = priv->bytes_per_row[0] << 3;
  bytes_per_mcu[0] = 8;

  return !priv->components[0];
}

static const struct tinyjpeg_colorspace format_grey =
  {
    {
      YCrCB_to_Grey_1xN,
      YCrCB_to_Grey_1xN,
      YCrCB_to_Grey_2xN,
      YCrCB_to_Grey_2xN,
    },
    tinyjpeg_decode_mcu_1comp_table,
    initialize_grey
  };

const tinyjpeg_colorspace_t TINYJPEG_FMT_GREY = &format_grey;
