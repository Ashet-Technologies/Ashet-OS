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
;; io.inc
;;
;; I/O related macros
;;

%ifndef _IO_INC
%define _IO_INC

%define IO_DELAY_PORT	80h		; Invalid port (we hope!)

%macro io_delay 0.nolist
		out IO_DELAY_PORT,al
		out IO_DELAY_PORT,al
%endmacro

%macro slow_out 2.nolist
		out %1,%2
		io_delay
%endmacro

%endif ; _IO_INC
