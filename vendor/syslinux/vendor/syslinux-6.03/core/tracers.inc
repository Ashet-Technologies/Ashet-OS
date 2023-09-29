;; -----------------------------------------------------------------------
;;
;;   Copyright 1994-2008 H. Peter Anvin - All Rights Reserved
;;
;;   This program is free software; you can redistribute it and/or modify
;;   it under the terms of the GNU General Public License as published by
;;   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
;;   Boston MA 02111-1307, USA; either version 2 of the License, or
;;   (at your option) any later version; incorporated herein by reference.
;;
;; -----------------------------------------------------------------------

;;
;; tracers.inc
;;
;; Debugging tracers
;;

%ifndef _TRACERS_INC
%define _TRACERS_INC

; Note: The Makefile builds one version with DEBUG_MESSAGES automatically.
; %define DEBUG_TRACERS 1		; Uncomment to get debugging tracers
; %define DEBUG_MESSAGES		; Uncomment to get debugging messages

%ifdef DEBUG_TRACERS

%macro TRACER	1
	call debug_tracer
	db %1
%endmacro

%else	; DEBUG_TRACERS

%macro	TRACER	1
%endmacro

%endif	; DEBUG_TRACERS

%endif ; _TRACERS_INC
