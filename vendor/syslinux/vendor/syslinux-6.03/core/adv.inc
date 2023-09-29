;; -----------------------------------------------------------------------
;;
;;   Copyright 2007-2008 H. Peter Anvin - All Rights Reserved
;;
;;   This program is free software; you can redistribute it and/or modify
;;   it under the terms of the GNU General Public License as published by
;;   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
;;   Boston MA 02110-1301, USA; either version 2 of the License, or
;;   (at your option) any later version; incorporated herein by reference.
;;
;; -----------------------------------------------------------------------

;;
;; adv.inc
;;
;; The auxillary data vector and its routines
;;
;; The auxillary data vector is a 512-byte aligned block that on the
;; disk-based derivatives can be part of the syslinux file itself.  It
;; exists in two copies; when written, both copies are written (with a
;; sync in between, if from the operating system.)  The first two
;; dwords are magic number and inverse checksum, then follows the data
;; area as a tagged array similar to BOOTP/DHCP, finally a tail
;; signature.
;;
;; Note that unlike BOOTP/DHCP, zero terminates the chain, and FF
;; has no special meaning.
;;

;;
;; List of ADV tags...
;;
ADV_BOOTONCE	equ 1

;;
;; Other ADV data...
;;
ADV_MAGIC1	equ 0x5a2d2fa5			; Head signature
ADV_MAGIC2	equ 0xa3041767			; Total checksum
ADV_MAGIC3	equ 0xdd28bf64			; Tail signature

ADV_LEN		equ 500				; Data bytes

adv_retries	equ 6				; Disk retries

		section .data
		global __syslinux_adv_ptr, __syslinux_adv_size
__syslinux_adv_ptr:
		dd adv0.data
__syslinux_adv_size:
		dd ADV_LEN

		section .adv
		; Introduce the ADVs to valid but blank
adv0:
.head		resd 1
.csum		resd 1
.data		resb ADV_LEN
.tail		resd 1
.end		equ $
adv1:
.head		resd 1
.csum		resd 1
.data		resb ADV_LEN
.tail		resd 1
.end		equ $
		section .text16

		;
		; This is called after config file parsing, so we know
		; the intended location of the ADV
		;
		global adv_init
adv_init:
		cmp byte [ADVDrive],-1
		jne adv_read

%if IS_SYSLINUX || IS_EXTLINUX
		cmp word [ADVSectors],2		; Not present?
		jb adv_verify

		mov eax,[Hidden]
		mov edx,[Hidden+4]
		add [ADVSec0],eax
		adc [ADVSec0+4],edx
		add [ADVSec1],eax
		adc [ADVSec1+4],edx
		mov al,[DriveNumber]
		mov [ADVDrive],al
		jmp adv_read
%endif

		;
		; Initialize the ADV data structure in memory
		;
adv_verify:
		cmp byte [ADVDrive],-1		; No ADV configured, still?
		je .reset			; Then unconditionally reset

		mov si,adv0
		call .check_adv
		jz .ok				; Primary ADV okay
		mov si,adv1
		call .check_adv
		jz .adv1ok

		; Neither ADV is usable; initialize to blank
.reset:
		mov di,adv0
		mov eax,ADV_MAGIC1
		stosd
		mov eax,ADV_MAGIC2
		stosd
		xor eax,eax
		mov cx,ADV_LEN/4
		rep stosd
		mov eax,ADV_MAGIC3
		stosd

.ok:
		ret

		; The primary ADV is bad, but the backup is OK
.adv1ok:
		mov di,adv0
		mov cx,512/4
		rep movsd
		ret


		; SI points to the putative ADV; unchanged by routine
		; ZF=1 on return if good
.check_adv:
		push si
		lodsd
		cmp eax,ADV_MAGIC1
		jne .done			; ZF=0, i.e. bad
		xor edx,edx
		mov cx,ADV_LEN/4+1		; Remaining dwords
.csum:
		lodsd
		add edx,eax
		loop .csum
		cmp edx,ADV_MAGIC2
		jne .done
		lodsd
		cmp eax,ADV_MAGIC3
.done:
		pop si
		ret

;
; adv_get: find an ADV string if present
;
; Input:	DL	= ADV ID
; Output:	CX	= byte count (zero on not found)
;		SI	= pointer to data
;		DL	= unchanged
;
; Assumes CS == DS.
;

adv_get:
		push ax
		mov si,adv0.data
		xor ax,ax			; Keep AH=0 at all times
.loop:
		lodsb				; Read ID
		cmp al,dl
		je .found
		and al,al
		jz .end
		lodsb				; Read length
		add si,ax
		cmp si,adv0.tail
		jb .loop
		jmp .end

.found:
		lodsb
		mov cx,ax
		add ax,si			; Make sure it fits
		cmp ax,adv0.tail
		jbe .ok
.end:
		xor cx,cx
.ok:
		pop ax
		ret

;
; adv_set: insert a string into the ADV in memory
;
; Input:	DL	= ADV ID
;		FS:BX	= input buffer
;		CX	= byte count (max = 255!)
; Output:	CF=1 on error
;		CX	clobbered
;
; Assumes CS == DS == ES.
;
adv_set:
		push ax
		push si
		push di
		and ch,ch
		jnz .overflow

		push cx
		mov si,adv0.data
		xor ax,ax
.loop:
		lodsb
		cmp al,dl
		je .found
		and al,al
		jz .endz
		lodsb
		add si,ax
		cmp si,adv0.tail
		jb .loop
		jmp .end

.found:		; Found, need to delete old copy
		lodsb
		lea di,[si-2]
		push di
		add si,ax
		mov cx,adv0.tail
		sub cx,si
		jb .nukeit
		rep movsb			; Remove the old one
		mov [di],ah			; Termination zero
		pop si
		jmp .loop
.nukeit:
		pop si
		jmp .end
.endz:
		dec si
.end:
		; Now SI points to where we want to put our data
		pop cx
		mov di,si
		jcxz .empty
		add si,cx
		cmp si,adv0.tail-2
		jae .overflow			; CF=0

		mov si,bx
		mov al,dl
		stosb
		mov al,cl
		stosb
		fs rep movsb

.empty:
		mov cx,adv0.tail
		sub cx,di
		xor ax,ax
		rep stosb			; Zero-fill remainder

		clc
.done:
		pop di
		pop si
		pop ax
		ret
.overflow:
		stc
		jmp .done

;
; adv_cleanup:	checksum adv0 and copy to adv1
;		Assumes CS == DS == ES.
;
adv_cleanup:
		pushad
		mov si,adv0.data
		mov cx,ADV_LEN/4
		xor edx,edx
.loop:
		lodsd
		add edx,eax
		loop .loop
		mov eax,ADV_MAGIC2
		sub eax,edx
		lea di,[si+4]			; adv1
		mov si,adv0
		mov [si+4],eax			; Store checksum
		mov cx,(ADV_LEN+12)/4
		rep movsd
		popad
		ret

;
; adv_write:	write the ADV to disk.
;
;		Location is in memory variables.
;		Assumes CS == DS == ES.
;
;		Returns CF=1 if the ADV cannot be written.
;
		global adv_write
adv_write:
		push eax
		mov eax,[ADVSec0]
		or eax,[ADVSec0+4]
		je .bad
		mov eax,[ADVSec1]
		or eax,[ADVSec1+4]
		je .bad
		cmp byte [ADVDrive],-1
		je .bad

		call adv_cleanup
		mov ah,3			; Write
		call adv_read_write

		clc
		pop eax
		ret
.bad:						; No location for ADV set
		stc
		pop eax
		ret

;
; adv_read:	read the ADV from disk
;
;		Location is in memory variables.
;		Assumes CS == DS == ES.
;
adv_read:
		push ax
		mov ah,2			; Read
		call adv_read_write
		call adv_verify
		pop ax
		ret

;
; adv_read_write: disk I/O for the ADV
;
;		On input, AH=2 for read, AH=3 for write.
;		Assumes CS == DS == ES.
;
adv_read_write:
		mov [ADVOp],ah
		pushad

		; Check for EDD
		mov bx,55AAh
		mov ah,41h			; EDD existence query
		mov dl,[ADVDrive]
		int 13h
		mov si,.cbios
		jc .noedd
		cmp bx,0AA55h
		jne .noedd
		test cl,1
		jz .noedd
		mov si,.ebios
.noedd:

		mov eax,[ADVSec0]
		mov edx,[ADVSec0+4]
		mov bx,adv0
		call .doone

		mov eax,[ADVSec1]
		mov edx,[ADVSec1+4]
		mov bx,adv1
		call .doone

		popad
		ret

.doone:
		push si
		jmp si

.ebios:
		mov cx,adv_retries
.eb_retry:
		; Form DAPA on stack
		push edx
		push eax
		push es
		push bx
		push word 1			; Sector count
		push word 16			; DAPA size
		mov si,sp
		pushad
		mov dl,[ADVDrive]
		mov ax,4000h
		or ah,[ADVOp]
		push ds
		push ss
		pop ds
		int 13h
		pop ds
		popad
		lea sp,[si+16]			; Remove DAPA
		jc .eb_error
		pop si
		ret
.eb_error:
		loop .eb_retry
		stc
		pop si
		ret

.cbios:
		push edx
		push eax
		push bp

		and edx,edx			; > 2 TiB not possible
		jnz .cb_overflow

		mov dl,[ADVDrive]
		and dl,dl
		; Floppies: can't trust INT 13h 08h, we better know
		; the geometry a priori, which means it better be our
		; boot device...
		jns .noparm			; Floppy drive... urk

		mov ah,08h			; Get disk parameters
		int 13h
		jc .noparm
		and ah,ah
		jnz .noparm
		shr dx,8
		inc dx
		movzx edi,dx			; EDI = heads
		and cx,3fh
		movzx esi,cx			; ESI = sectors/track
		jmp .parmok

.noparm:
		; No CHS info... this better be our boot drive, then
%if IS_SYSLINUX || IS_EXTLINUX
		cmp dl,[DriveNumber]
		jne .cb_overflow		; Fatal error!
		movzx esi,word [bsSecPerTrack]
		movzx edi,word [bsHeads]
%else
		; Not a disk-based derivative... there is no hope
		jmp .cb_overflow
%endif

.parmok:
                ;
                ; Dividing by sectors to get (track,sector): we may have
                ; up to 2^18 tracks, so we need to use 32-bit arithmetric.
                ;
		xor edx,edx
                div esi
                xor cx,cx
                xchg cx,dx              ; CX <- sector index (0-based)
                                        ; EDX <- 0
                ; eax = track #
                div edi                 ; Convert track to head/cyl

		; Watch out for overflow, we might be writing!
		cmp eax,1023
                ja .cb_overflow

                ;
                ; Now we have AX = cyl, DX = head, CX = sector (0-based),
                ; BP = sectors to transfer, SI = bsSecPerTrack,
                ; ES:BX = data target
                ;

                shl ah,6                ; Because IBM was STOOPID
                                        ; and thought 8 bits were enough
                                        ; then thought 10 bits were enough...
                inc cx                  ; Sector numbers are 1-based, sigh
                or cl,ah
                mov ch,al
                mov dh,dl
                mov dl,[ADVDrive]
		mov al,01h		; Transfer one sector
                mov ah,[ADVOp]		; Operation

		mov bp,adv_retries
.cb_retry:
                pushad
                int 13h
                popad
                jc .cb_error

.cb_done:
                pop bp
                pop eax
                pop edx
		pop si
                ret

.cb_error:
                dec bp
                jnz .cb_retry
.cb_overflow:
		stc
		jmp .cb_done

		section .data16
		alignz 8
ADVSec0		dq 0			; Not specified
ADVSec1		dq 0			; Not specified
ADVDrive	db -1			; No ADV defined
ADVCHSInfo	db -1			; We have CHS info for this drive

		section .bss16
ADVOp		resb 1

		section .text16
