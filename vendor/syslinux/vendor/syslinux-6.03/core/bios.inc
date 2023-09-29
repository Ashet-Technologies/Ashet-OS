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
;; bios.inc
;;
;; Header file for the BIOS data structures etc.
;;

%ifndef _BIOS_INC
%define _BIOS_INC

		; Interrupt vectors
		absolute 4*1Ch
BIOS_timer_hook	resd 1

		absolute 4*1Eh
fdctab		equ $
fdctab1		resw 1
fdctab2		resw 1

		absolute 0400h
serial_base	resw 4			; Base addresses for 4 serial ports
		absolute 0413h
BIOS_fbm	resw 1			; Free Base Memory (kilobytes)
		absolute 0462h
BIOS_page	resb 1			; Current video page
		absolute 046Ch
BIOS_timer	resw 1			; Timer ticks
		absolute 0472h
BIOS_magic	resw 1			; BIOS reset magic
                absolute 0484h
BIOS_vidrows    resb 1			; Number of screen rows

%endif ; _BIOS_INC
