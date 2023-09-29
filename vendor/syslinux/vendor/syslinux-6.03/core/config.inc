;; -----------------------------------------------------------------------
;;
;;   Copyright 2002-2009 H. Peter Anvin - All Rights Reserved
;;   Copyright 2009 Intel Corporation; author: H. Peter Anvin
;;
;;   This program is free software; you can redistribute it and/or modify
;;   it under the terms of the GNU General Public License as published by
;;   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
;;   Boston MA 02111-1307, USA; either version 2 of the License, or
;;   (at your option) any later version; incorporated herein by reference.
;;
;; -----------------------------------------------------------------------

;;
;; config.inc
;;
;; Common configuration options.  Some of these are imposed by the kernel.
;;

%ifndef _CONFIG_INC
%define _CONFIG_INC

max_cmd_len	equ 2047		; Must be &3; 2047 is the kernel limit
HIGHMEM_MAX	equ 037FFFFFFh		; DEFAULT highest address for an initrd
DEFAULT_BAUD	equ 9600		; Default baud rate for serial port
BAUD_DIVISOR	equ 115200		; Serial port parameter
MAX_FKEYS	equ 12			; Number of F-key help files

;
; log2(Max filename size Including final null)
;
FILENAME_MAX_LG2 equ 8
FILENAME_MAX	 equ (1 << FILENAME_MAX_LG2)	; Max mangled filename size

;
; Version number definitinons
;
%include "../version.gen"

%endif ; _CONFIG_INC
