;; -----------------------------------------------------------------------
;;
;;   Copyright 1994-2009 H. Peter Anvin - All Rights Reserved
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
;; bcopy32.inc
;;
;; 32-bit bcopy routine for real mode
;;

;
; 32-bit bcopy routine for real mode
;
; We enter protected mode, set up a flat 32-bit environment, run rep movsd
; and then exit.  IMPORTANT: This code assumes cs == 0.
;
; This code is probably excessively anal-retentive in its handling of
; segments, but this stuff is painful enough as it is without having to rely
; on everything happening "as it ought to."
;

		bits 16
		section .text16

;
; bcopy:
;	32-bit copy, overlap safe
;
; Inputs:
;	ESI	- source pointer (-1 means do bzero rather than bcopy)
;	EDI	- target pointer
;	ECX	- byte count
;
; Outputs:
;	ESI	- first byte after source (garbage if ESI == -1 on entry)
;	EDI	- first byte after target
;
bcopy:		jecxz .ret
		pm_call pm_bcopy
		add edi,ecx
		add esi,ecx
.ret:		ret

;
; shuffle_and_boot_raw:
;	The new version of shuffle and boot.
; Inputs:
;	ESI		-> Pointer to list of (dst, src, len) pairs(*)
;	EDI		-> Pointer to safe area for list + shuffler
;			   (must not overlap this code nor the RM stack)
;	ECX		-> Byte count of list area (for initial copy)
;
;     If src == -1: then the memory pointed to by (dst, len) is bzeroed;
;		    this is handled inside the bcopy routine.
;
;     If len == 0:  this marks the end of the list; dst indicates
;		    the entry point and src the mode (0 = pm, 1 = rm)
;
;     (*) dst, src, and len are four bytes each
;
shuffle_and_boot_raw:
		mov bx,pm_shuffle
		jmp enter_pm

;
; The 32-bit copy and shuffle code is "special", so it is in its own file
;
%include "bcopyxx.inc"
