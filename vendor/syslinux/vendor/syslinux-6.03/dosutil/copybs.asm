; -*- fundamental -*- (asm-mode sucks)
; -----------------------------------------------------------------------
;
;   Copyright 1998-2008 H. Peter Anvin - All Rights Reserved
;
;   This program is free software; you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
;   Boston MA 02111-1307, USA; either version 2 of the License, or
;   (at your option) any later version; incorporated herein by reference.
;
; -----------------------------------------------------------------------

;
; copybs.asm
;
; Small DOS program to copy the boot sector from a drive
; to a file
;
; Usage: copybs <drive>: <file>
;

		absolute 0
pspInt20:		resw 1
pspNextParagraph:	resw 1
			resb 1		; reserved
pspDispatcher:		resb 5
pspTerminateVector:	resd 1
pspControlCVector:	resd 1
pspCritErrorVector:	resd 1
			resw 11		; reserved
pspEnvironment:		resw 1
			resw 23		; reserved
pspFCB_1:		resb 16
pspFCB_2:		resb 16
			resd 1		; reserved
pspCommandLen:		resb 1
pspCommandArg:		resb 127

		section .text
		org 100h			; .COM format
_start:
		mov ax,3000h			; Get DOS version
		int 21h
		xchg al,ah
		mov [DOSVersion],ax
		cmp ax,0200h			; DOS 2.00 minimum
		jae dosver_ok
		mov dx,msg_ancient_err
		jmp die

		section .bss
		alignb 2
DOSVersion:	resw 1

		section .text
;
; Scan command line for a drive letter followed by a colon
;
dosver_ok:
		xor cx,cx
		mov si,pspCommandArg
		mov cl,[pspCommandLen]

cmdscan1:	jcxz bad_usage			; End of command line?
		lodsb				; Load character
		dec cx
		cmp al,' '			; White space
		jbe cmdscan1
		or al,020h			; -> lower case
		cmp al,'a'			; Check for letter
		jb bad_usage
		cmp al,'z'
		ja bad_usage
		sub al,'a'			; Convert to zero-based index
		mov [DriveNo],al		; Save away drive index

		section .bss
DriveNo:	resb 1

		section .text
;
; Got the leading letter, now the next character must be a colon
;
got_letter:	jcxz bad_usage
		lodsb
		dec cx
		cmp al,':'
		jne bad_usage
;
; Got the colon; now we should have at least one whitespace
; followed by a filename
;
got_colon:	jcxz bad_usage
		lodsb
		dec cx
		cmp al,' '
		ja bad_usage

skipspace:	jcxz bad_usage
		lodsb
		dec cx
		cmp al,' '
		jbe skipspace

		mov di,FileName
copyfile:	stosb
		jcxz got_cmdline
		lodsb
		dec cx
		cmp al,' '
		ja copyfile
		jmp short got_cmdline

;
; We end up here if the command line doesn't parse
;
bad_usage:	mov dx,msg_unfair
		jmp die

		section .data
msg_unfair:	db 'Usage: copybs <drive>: <filename>', 0Dh, 0Ah, '$'

		section .bss
		alignb 4
FileName	resb 256

;
; Parsed the command line OK.  Get device parameter block to get the
; sector size.
;
		struc DPB
dpbDrive:	resb 1
dpbUnit:	resb 1
dpbSectorSize:	resw 1
dpbClusterMask:	resb 1
dpbClusterShift: resb 1
dpbFirstFAT:	resw 1
dpbFATCount:	resb 1
dpbRootEntries:	resw 1
dpbFirstSector:	resw 1
dpbMaxCluster:	resw 1
dpbFATSize:	resw 1
dpbDirSector:	resw 1
dpbDriverAddr:	resd 1
dpbMedia:	resb 1
dpbFirstAccess:	resb 1
dpbNextDPB:	resd 1
dpbNextFree:	resw 1
dpbFreeCnt:	resw 1
		endstruc

		section .bss
		alignb 2
SectorSize	resw 1

		section .text
got_cmdline:
		xor al,al			; Zero-terminate filename
		stosb

		mov dl,[DriveNo]
		inc dl				; 1-based
		mov ah,32h
		int 21h				; Get Drive Parameter Block

		and al,al
		jnz filesystem_error

		mov dx,[bx+dpbSectorSize]	; Save sector size
;
; Read the boot sector.
;
		section .data
		align 4, db 0
DISKIO		equ $
diStartSector:	dd 0				; Absolute sector 0
diSectors:	dw 1				; One sector
diBuffer:	dw SectorBuffer			; Buffer offset
		dw 0				; Buffer segment

		section .text
read_bootsect:
		mov ax,cs			; Set DS <- CS
		mov ds,ax

		mov [SectorSize],dx		; Saved sector size from above

		cmp word [DOSVersion],0400h	; DOS 4.00 has a new interface
		jae .new
.old:
		mov bx,SectorBuffer
		mov cx,1			; One sector
		jmp short .common
.new:
		mov [diBuffer+2],ax		; == DS
		mov bx,DISKIO
		mov cx,-1
.common:
		xor dx,dx			; Absolute sector 0
		mov al,[DriveNo]
		int 25h				; DOS absolute disk read
		pop ax				; Remove flags from stack
		jc disk_read_error

;
; Open the file and write the boot sector to the file.
;
		mov dx,FileName
		mov cx,0020h			; Attribute = ARCHIVE
		mov ah,3Ch			; Create file
		int 21h
		jc file_write_error

		mov bx,ax
		push ax				; Handle

		mov cx,[SectorSize]
		mov dx,SectorBuffer
		mov ah,40h			; Write file
		int 21h
		jc file_write_error
		cmp ax,[SectorSize]
		jne file_write_error

		pop bx				; Handle
		mov ah,3Eh			; Close file
		int 21h
		jc file_write_error
;
; We're done!
;
		mov ax,4C00h			; exit(0)
		int 21h

;
; Error routine jump
;
filesystem_error:
		mov dx,msg_filesystem_err
		jmp short die
disk_read_error:
		mov dx,msg_read_err
		jmp short die
file_write_error:
		mov dx,msg_write_err
die:
		push cs
		pop ds
		push dx
		mov dx,msg_error
		mov ah,09h
		int 21h
		pop dx

		mov ah,09h			; Write string
		int 21h

		mov ax,4C01h			; Exit error status
		int 21h

		section .data
msg_error:		db 'ERROR: $'
msg_ancient_err:	db 'DOS version 2.00 or later required', 0Dh, 0Ah, '$'
msg_filesystem_err:	db 'Filesystem not found on disk', 0Dh, 0Ah, '$'
msg_read_err:		db 'Boot sector read failed', 0Dh, 0Ah, '$'
msg_write_err:		db 'File write failed', 0Dh, 0Ah, '$'

		section .bss
		alignb 4
SectorBuffer:	resb 4096
