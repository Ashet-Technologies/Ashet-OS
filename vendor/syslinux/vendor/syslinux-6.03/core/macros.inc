;; -----------------------------------------------------------------------
;;
;;   Copyright 1994-2008 H. Peter Anvin - All Rights Reserved
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
;; macros.inc
;;
;; Convenient macros
;;

%ifndef _MACROS_INC
%define _MACROS_INC

;
; Identify the module we're compiling; the "correct" should be defined
; in the module itself to 1
;
%ifdef IS_SYSLINUX
 %define MY_NAME 'SYSLINUX'
%else
 %define IS_SYSLINUX 0
%endif
%ifdef IS_PXELINUX
 %define MY_NAME 'PXELINUX'
 %if IS_LPXELINUX > 0
  %define MY_TYPE 'lwIP'
 %else
  %define MY_TYPE 'PXE'
 %endif
%else
 %define IS_PXELINUX 0
%endif
%ifdef IS_ISOLINUX
 %define MY_NAME 'ISOLINUX'
%else
 %define IS_ISOLINUX 0
%endif
%ifdef IS_EXTLINUX
 %define MY_NAME 'EXTLINUX'
%else
 %define IS_EXTLINUX 0
%endif

;
; Macros similar to res[bwd], but which works in the code segment (after
; section .text16) or the data segment (section .data16)
;
%macro	zb	1.nolist
	times %1 db 0
%endmacro

%macro	zw	1.nolist
	times %1 dw 0
%endmacro

%macro	zd	1.nolist
	times %1 dd 0
%endmacro

;
; Align with zero bytes in a progbits segment
;
%macro	alignz	1.nolist
	times (((%1) - (($-$$) % (%1))) % (%1)) db 0
%endmacro

;
; Macro to emit an unsigned decimal number as a string
;
%macro asciidec	1.nolist
  %ifndef DEPEND	; Not safe for "depend"
    %push asciidec
      %assign %$v %1
      %if %$v == 0
        db '0'
      %else
        %assign %$dcount 0
        %assign %$n %$v
        %assign %$d 1
        %rep 20
          %if %$n != 0
            %assign %$dcount %$dcount + 1
            %assign %$n %$n / 10
            %assign %$d %$d * 10
          %endif
        %endrep
        %rep %$dcount
	  %assign %$d %$d / 10
          db ((%$v / %$d) % 10) + '0'
        %endrep
      %endif
    %pop
  %endif
%endmacro

;
; Macros for network byte order of constants
;
%define htons(x)  ( ( ((x) & 0FFh) << 8 ) + ( ((x) & 0FF00h) >> 8 ) )
%define ntohs(x) htons(x)
%define htonl(x)  ( ( ((x) & 0FFh) << 24) + ( ((x) & 0FF00h) << 8 ) + ( ((x) & 0FF0000h) >> 8 ) + ( ((x) & 0FF000000h) >> 24) )
%define ntohl(x) htonl(x)

;
; ASCII
;
CR		equ 13		; Carriage Return
LF		equ 10		; Line Feed
FF		equ 12		; Form Feed
BS		equ  8		; Backspace

%endif ; _MACROS_INC
