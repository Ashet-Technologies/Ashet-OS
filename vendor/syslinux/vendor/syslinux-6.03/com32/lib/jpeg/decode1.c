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

/*
 * Decode a 1x1 directly in 1 color
 */
static void decode_MCU_1x1_1plane(struct jdec_private *priv)
{
  // Y
  tinyjpeg_process_Huffman_data_unit(priv, cY);
  IDCT(&priv->component_infos[cY], priv->Y, 8);

  // Cb
  tinyjpeg_process_Huffman_data_unit(priv, cCb);
  IDCT(&priv->component_infos[cCb], priv->Cb, 8);

  // Cr
  tinyjpeg_process_Huffman_data_unit(priv, cCr);
  IDCT(&priv->component_infos[cCr], priv->Cr, 8);
}


/*
 * Decode a 2x1
 *  .-------.
 *  | 1 | 2 |
 *  `-------'
 */
static void decode_MCU_2x1_1plane(struct jdec_private *priv)
{
  // Y
  tinyjpeg_process_Huffman_data_unit(priv, cY);
  IDCT(&priv->component_infos[cY], priv->Y, 16);
  tinyjpeg_process_Huffman_data_unit(priv, cY);
  IDCT(&priv->component_infos[cY], priv->Y+8, 16);

  // Cb
  tinyjpeg_process_Huffman_data_unit(priv, cCb);

  // Cr
  tinyjpeg_process_Huffman_data_unit(priv, cCr);
}


/*
 * Decode a 2x2 directly in GREY format (8bits)
 *  .-------.
 *  | 1 | 2 |
 *  |---+---|
 *  | 3 | 4 |
 *  `-------'
 */
static void decode_MCU_2x2_1plane(struct jdec_private *priv)
{
  // Y
  tinyjpeg_process_Huffman_data_unit(priv, cY);
  IDCT(&priv->component_infos[cY], priv->Y, 16);
  tinyjpeg_process_Huffman_data_unit(priv, cY);
  IDCT(&priv->component_infos[cY], priv->Y+8, 16);
  tinyjpeg_process_Huffman_data_unit(priv, cY);
  IDCT(&priv->component_infos[cY], priv->Y+64*2, 16);
  tinyjpeg_process_Huffman_data_unit(priv, cY);
  IDCT(&priv->component_infos[cY], priv->Y+64*2+8, 16);

  // Cb
  tinyjpeg_process_Huffman_data_unit(priv, cCb);

  // Cr
  tinyjpeg_process_Huffman_data_unit(priv, cCr);
}

/*
 * Decode a 1x2 mcu
 *  .---.
 *  | 1 |
 *  |---|
 *  | 2 |
 *  `---'
 */
static void decode_MCU_1x2_1plane(struct jdec_private *priv)
{
  // Y
  tinyjpeg_process_Huffman_data_unit(priv, cY);
  IDCT(&priv->component_infos[cY], priv->Y, 8);
  tinyjpeg_process_Huffman_data_unit(priv, cY);
  IDCT(&priv->component_infos[cY], priv->Y+64, 8);

  // Cb
  tinyjpeg_process_Huffman_data_unit(priv, cCb);

  // Cr
  tinyjpeg_process_Huffman_data_unit(priv, cCr);
}

const decode_MCU_fct tinyjpeg_decode_mcu_1comp_table[4] = {
   decode_MCU_1x1_1plane,
   decode_MCU_1x2_1plane,
   decode_MCU_2x1_1plane,
   decode_MCU_2x2_1plane,
};
