;
; Modules common to all derivatives.  Do not include modules in this list
; which have special section requirements (i.e. need to be in .init for
; some derivatives.)
;

%include "pm.inc"		; Protected mode
%include "bcopy32.inc"		; 32-bit bcopy
%include "strcpy.inc"           ; strcpy()
%include "adv.inc"		; Auxillary Data Vector
%include "timer.inc"		; Timer handling

; Note: the prefix section is included late, to avoid problems with some
; versions of NASM that had issues with forward references to EQU symbols.
%include "prefix.inc"		; Prefix section for prepcore
