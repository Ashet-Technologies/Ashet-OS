; -*- fundamental -*- (asm-mode sucks)
; ****************************************************************************
;
;  memdisk.inc
;
;  A program to emulate an INT 13h disk BIOS from a "disk" in extended
;  memory.
;
;   Copyright 2001-2009 H. Peter Anvin - All Rights Reserved
;   Copyright 2009 Intel Corporation; author: H. Peter Anvin
;   Portions copyright 2009 Shao Miller [El Torito code, mBFT, safe hook]
;
;  This program is free software; you can redistribute it and/or modify
;  it under the terms of the GNU General Public License as published by
;  the Free Software Foundation, Inc., 53 Temple Place Ste 330,
;  Boston MA 02111-1307, USA; either version 2 of the License, or
;  (at your option) any later version; incorporated herein by reference.
;
; ****************************************************************************

%include "../version.gen"

; %define DEBUG_TRACERS			; Uncomment to get debugging tracers

%ifdef DEBUG_TRACERS

%macro TRACER	1
	call debug_tracer
	db %1
%endmacro
%macro WRITEHEX2 0-1 al
%ifnidni %1,al
	push ax
	mov al,%1
	call writehex2
	pop ax
%else
	call writehex2
%endif
%endmacro
%macro WRITEHEX4 0-1 ax
%ifnidni %1,ax
	push ax
	mov ax,%1
	call writehex4
	pop ax
%else
	call writehex4
%endif
%endmacro
%macro WRITEHEX8 0-1 eax
%ifnidni %1,eax
	push eax
	mov eax,%1
	call writehex8
	pop eax
%else
	call writehex8
%endif
%endmacro

%else	; DEBUG_TRACERS

%macro	TRACER	1
%endmacro
%macro WRITEHEX2 0-1
%endmacro
%macro WRITEHEX4 0-1
%endmacro
%macro WRITEHEX8 0-1
%endmacro

%endif	; DEBUG_TRACERS

; Flags we test our configuration against
%define CONFIG_READONLY	0x01
%define CONFIG_RAW	0x02
%define CONFIG_SAFEINT	0x04
%define CONFIG_BIGRAW	0x08		; MUST be 8!

		org 0h

%define	SECTORSIZE	(1 << SECTORSIZE_LG2)

		; Parameter registers definition; this is the definition
		; of the stack frame.
%define		P_DS		word [bp+34]
%define		P_ES		word [bp+32]
%define		P_EAX		dword [bp+28]
%define		P_HAX		word [bp+30]
%define		P_AX		word [bp+28]
%define		P_AL		byte [bp+28]
%define		P_AH		byte [bp+29]
%define		P_ECX		dword [bp+24]
%define		P_HCX		word [bp+26]
%define		P_CX		word [bp+24]
%define		P_CL		byte [bp+24]
%define		P_CH		byte [bp+25]
%define		P_EDX		dword [bp+20]
%define		P_HDX		word [bp+22]
%define		P_DX		word [bp+20]
%define		P_DL		byte [bp+20]
%define		P_DH		byte [bp+21]
%define		P_EBX		dword [bp+16]
%define		P_HBX		word [bp+18]
%define		P_HBXL		byte [bp+18]
%define		P_BX		word [bp+16]
%define		P_BL		byte [bp+16]
%define		P_BH		byte [bp+17]
%define		P_EBP		dword [bp+8]
%define		P_BP		word [bp+8]
%define		P_ESI		dword [bp+4]
%define		P_SI		word [bp+4]
%define		P_EDI		dword [bp]
%define		P_DI		word [bp]

		section .text
		; These pointers are used by the installer and
		; must be first in the binary
Pointers:	dw Int13Start
		dw Int15Start
		dw MemDisk_Info		; Portions are patched by installer
		dw TotalSize
		dw IretPtr

IretPtr		equ Int13Start.iret
Int13Start:
		jmp strict near .SafeHookEnd ; 3-byte jump
		db '$INT13SF'		; Signature for "safe hook"
		db 'MEMDISK '		; Vendor ID
		dd 0			; SEG:OFF of previous INT 13h hook
					; Must be filled in by installer
		dd 0			; "Safe hook" flags
; ---- "Safe hook" structure ends here ---

; This next field should be guaranteed at this position after the
; "safe hook" structure.  This allows for a MEMDISK OS driver to
; immediately find out the particular parameters using the mBFT
; and MDI structures.  This binary will have the offset to the mBFT
; in this field to begin with, so the installer knows where the mBFT
; is.  This is akin to the "Pointers" section above.  The installer
; will refill this field with the physical address of the mBFT for
; future consumers, such as OS drivers.
		dd mBFT			; Offset from hook to the mBFT

.SafeHookEnd:
		cmp word [cs:Recursive],0
		jne recursive

		; Swap stack
		mov [cs:Stack],esp
		mov [cs:Stack+4],ss
		mov [cs:SavedAX],ax
		mov ax,cs
		mov ss,ax
		mov sp,[cs:MyStack]

%if ELTORITO
		cmp word [cs:SavedAX],4a00h	; El Torito function?
		jae our_drive			; We grab it
%endif
		; See if DL points to our class of device (FD, HD)
		push dx
		push dx
		xor dl,[cs:DriveNo]
		pop dx
		js .nomatch		; If SF=0, we have a class match here
					; 0x00 the sign bit for FD
					; 0x80 the sign bit for HD
		jz our_drive		; If ZF=1, we have an exact match
		cmp dl,[cs:DriveNo]
		jb .nomatch		; Drive < Our drive
		cmp dl,[cs:DriveShiftLimit]
		jae .nomatch		; Drive > The maximum drive
					; number that we will shift for.
					; This leaves any higher-up BIOS
					; drives alone, such as an optical
					; disc drive 0xA0 or 0xE0
		dec dl			; Drive > Our drive, adjust drive #
.nomatch:
		TRACER '!'
		WRITEHEX2 dl
		TRACER ','
		mov ax,[cs:SavedAX]
		WRITEHEX4
		inc word [cs:Recursive]
		pushf
		call far [cs:OldInt13]
		pushf
		dec word [cs:Recursive]
		push bp
		mov bp,sp
		cmp byte [cs:SavedAX+1],08h	; Get drive params function?
		je .norestoredl			; DL = number of drives
		cmp byte [cs:SavedAX+1],15h	; Get disk type function?
		jne .restoredl
		test byte [bp+4],80h		; Hard disk?
		jnz .norestoredl		; CX:DX = size of device
.restoredl:
		mov dl,[bp+4]
.norestoredl:
		push ax
		push ebx
		push ds
		mov ax,[bp+2]		; Flags
		lds ebx,[cs:Stack]
		mov [bx+4],al		; Arithmetic flags
		pop ds
		pop ebx
		pop ax
		pop bp
		lss esp,[cs:Stack]
.iret:		iret

recursive:
		TRACER '@'
jmp_oldint13:
		jmp far [cs:OldInt13]

our_drive:
		; Set up standard entry frame
		push ds
		push es
		mov ds,ax
		mov es,ax
		mov ax,[SavedAX]
		pushad
		mov bp,sp		; Point BP to the entry stack frame
		TRACER 'F'
		WRITEHEX4
		; Note: AX == P_AX here
		cmp ah,Int13FuncsCnt-1
		ja Invalid_jump
%if ELTORITO
		mov al,[CD_PKT.type]	; Check if we are in
		cmp al,0		; El Torito no emulation mode
		ja .emulation		; No.  We support the function
		cmp ah,3fh		; Yes.  We must not support functions
		jbe Invalid_jump	; 0 through 3Fh.  Check and decide
.emulation:
%endif
		xor al,al		; AL = 0 is standard entry condition
		mov di,ax
		shr di,7		; Convert AH to an offset in DI
		call [Int13Funcs+di]

Done:		; Standard routine for return
		mov P_AX,ax
DoneWeird:
		TRACER 'D'
		xor bx,bx
		mov es,bx
		mov bx,[StatusPtr]
		mov [es:bx],ah		; Save status
		and ah,ah

		lds ebx,[Stack]
		; This sets the low byte (the arithmetic flags) of the
		; FLAGS on stack to either 00h (no flags) or 01h (CF)
		; depending on if AH was zero or not.
		setnz [bx+4]		; Set CF iff error
		popad
		pop es
		pop ds
		lss esp,[cs:Stack]
		iret

Reset:
		; Reset affects multiple drives, so we need to pass it on
		TRACER 'R'
		xor ax,ax		; Bottom of memory
		mov es,ax
		test dl,dl		; Always pass it on if we are
					; resetting HD
		js .hard_disk		; Bit 7 set
		; Some BIOSes get very unhappy if we pass a reset floppy
		; command to them and don't actually have any floppies.
		; This is a bug, but we have to deal with it nontheless.
		; Therefore, if we are the *ONLY* floppy drive, and the
		; user didn't request HD reset, then just drop the command.
		; BIOS equipment byte, top two bits + 1 == total # of floppies
		test byte [es:0x410],0C0h
		jz success
		jmp .pass_on		; ... otherwise pass it to the BIOS
.hard_disk:
		; ... same thing for hard disks, sigh ...
		cmp byte [es:0x475],1	; BIOS variable for number of hard
					; disks
		jbe success

.pass_on:
		pop ax			; Drop return address
		popad			; Restore all registers
		pop es
		pop ds
		lss esp,[cs:Stack]	; Restore the stack
		and dl,80h		; Clear all but the type bit
		jmp jmp_oldint13


Invalid:
		pop dx			; Drop return address
Invalid_jump:
		TRACER 'I'
		mov ah,01h		; Unsupported function
		jmp short Done

GetDriveType:
		test byte [DriveNo],80h
		mov bl,02h		; Type 02h = floppy with changeline
		jz .floppy
		; Hard disks only!  DO NOT set CX:DX for floppies...
		; it apparently causes Win98SE DOS to go into an loop
		; resetting the drive over and over.  Sigh.
		inc bx			; Type = 03h
		mov dx,[DiskSize]	; Return the disk size in sectors
		mov P_DX,dx
		mov cx,[DiskSize+2]
		mov P_CX,cx
.floppy:
		mov P_AH,bl		; 02h floppy, 03h hard disk
		pop ax			; Drop return address
		xor ax,ax		; Success...
		jmp DoneWeird		; But don't stick it into P_AX

GetStatus:
		xor ax,ax
		mov es,ax
		mov bx,[StatusPtr]
		mov ah,[bx]		; Copy last status
		ret

ReadMult:
		TRACER 'm'
Read:
		TRACER 'R'
		call setup_regs
do_copy:
		TRACER '<'
		call bcopy
		TRACER '>'
		movzx ax,P_AL		; AH = 0, AL = transfer count
		ret

WriteMult:
		TRACER 'M'
Write:
		TRACER 'W'
		test byte [ConfigFlags],CONFIG_READONLY
		jnz .readonly
		call setup_regs
		xchg esi,edi		; Opposite direction of a Read!
		jmp short do_copy
.readonly:	mov ah,03h		; Write protected medium
		ret

		; Verify integrity; just bounds-check
Seek:
Verify:
		call setup_regs		; Returns error if appropriate
		; And fall through to success

CheckIfReady:				; These are always-successful noop functions
Recalibrate:
InitWithParms:
DetectChange:
EDDDetectChange:
EDDLock:
SetMode:
success:
		xor ax,ax		; Always successful
		ret

GetParms:
		TRACER 'G'
		mov dl,[DriveCnt]	; Cached data
		mov P_DL,dl
		test byte [DriveNo],80h
		jnz .hd
		mov P_DI,DPT
		mov P_ES,cs
		mov bl,[DriveType]
		mov P_BL,bl
.hd:
		mov ax,[Cylinders]
		dec ax			; We report the highest #, not the count
		xchg al,ah
		shl al,6
		or al,[Sectors]
		mov P_CX,ax
		mov ax,[Heads]
		dec ax
		mov P_DH,al

		;
		; Is this MEMDISK installation check?
		;
		cmp P_HAX,'ME'
		jne .notic
		cmp P_HCX,'MD'
		jne .notic
		cmp P_HDX,'IS'
		jne .notic
		cmp P_HBX,'K?'
		jne .notic

		; MEMDISK installation check...
		mov P_HAX,'!M'
		mov P_HCX,'EM'
		mov P_HDX,'DI'
		mov P_HBX,'SK'
		mov P_ES,cs
		mov P_DI,MemDisk_Info

.notic:
		xor ax,ax
		ret
;
; EDD functions -- only if enabled
;
%if EDD
EDDPresence:
		TRACER 'E'
		TRACER 'c'

		cmp P_BX,55AAh
		jne Invalid
		mov P_BX,0AA55h		; EDD signature
		mov P_AX,03000h		; EDD 3.0
		mov P_CX,0007h		; Bit 0 - Fixed disk access subset
					; Bit 1 - Locking and ejecting subset
					; Bit 2 - EDD subset
		pop ax			; Drop return address
		xor ax,ax		; Success
		jmp DoneWeird		; Success, but AH != 0, sigh...

EDDRead:
		TRACER 'E'
		TRACER 'r'

		call edd_setup_regs
		call bcopy
		xor ax,ax
		ret

EDDWrite:
		TRACER 'E'
		TRACER 'w'

		call edd_setup_regs
		xchg esi,edi		; Opposite direction of a Read!
		call bcopy
		xor ax,ax
		ret

EDDVerify:
EDDSeek:
		call edd_setup_regs	; Just bounds checking
		xor ax,ax
		ret

EDDGetParms:
		TRACER 'E'
		TRACER 'p'

		mov es,P_DS
		mov di,P_SI
		mov si,EDD_DPT

		lodsw			; Length of our DPT
		mov cx,[es:di]
		cmp cx,26		; Minimum size
		jb .overrun

		cmp cx,ax
		jb .oksize
		mov cx,ax

.oksize:
		mov ax,cx
		stosw
		dec cx
		dec cx
		rep movsb

		xor ax,ax
		ret

.overrun:
		mov ax,0100h
		ret
%endif ; EDD

		; Set up registers as for a "Read", and compares against disk
		; size.
		; WARNING: This fails immediately, even if we can transfer some
		; sectors.  This isn't really the correct behaviour.
setup_regs:

		; Convert a CHS address in P_CX/P_DH into an LBA in eax
		; CH = cyl[7:0]
		; CL[0:5] = sector (1-based)  CL[7:6] = cyl[9:8]
		; DH = head
		movzx ecx,P_CX
		movzx ebx,cl		; Sector number
		and bl,3Fh
		dec ebx			; Sector number is 1-based
		cmp bx,[Sectors]
		jae .overrun
		movzx edi,P_DH		; Head number
		movzx eax,word [Heads]
		cmp di,ax
		jae .overrun
		shr cl,6
		xchg cl,ch		; Now (E)CX <- cylinder number
		mul ecx			; eax <- Heads*cyl# (edx <- 0)
		add eax,edi
		mul dword [Sectors]
		add eax,ebx
		; Now eax = LBA, edx = 0

		;
		; setup_regs continues...
		;
		; Note: edi[31:16] and ecx[31:16] = 0 already
		mov di,P_BX		; Get linear address of target buffer
		mov cx,P_ES
		shl ecx,4
		add edi,ecx		; EDI = address to fetch to
		movzx ecx,P_AL		; Sector count
		mov esi,eax
		add eax,ecx		; LBA of final sector + 1
		shl esi,SECTORSIZE_LG2	; LBA -> byte offset
		add esi,[DiskBuf]	; Get address in high memory
		cmp eax,[DiskSize]	; Check the high mark against limit
		ja .overrun
		shl ecx,SECTORSIZE_LG2-2 ; Convert count to dwords
		ret

.overrun:	pop ax			; Drop setup_regs return address
		mov ax,0200h		; Missing address mark
		ret			; Return to Done

		; Set up registers as for an EDD Read, and compares against disk size.
%if EDD
edd_setup_regs:
		push es
		mov si,P_SI		; DS:SI -> DAPA
		mov es,P_DS

		mov dx,[es:si]
		cmp dx,16
		jb .baddapa

		cmp dword [es:si+4],-1
		je .linear_address

		movzx ebx,word [es:si+4]	; Offset
		movzx edi,word [es:si+6]	; Segment
		shl edi,4
		add ebx,edi
		jmp .got_address

.linear_address:
		cmp dx,24		; Must be large enough to hold
					; linear address
		jb .baddapa

		cmp dword [es:si+20],0	; > 4 GB addresses not supported
		mov ax,0900h		; "Data boundary error" - bogus, but
					; no really better code available
		jne .error

		mov ebx,[es:si+16]

.got_address:
		cmp dword [es:si+12],0		; LBA too large?
		jne .overrun

		movzx ecx, word [es:si+2]	; Sectors to transfer
		mov esi,[es:si+8]		; Starting sector
		mov eax,esi
		add eax,ecx
		jc .overrun
		cmp eax,[DiskSize]
		ja .overrun

		shl ecx,SECTORSIZE_LG2-2	; Convert to dwords
		shl esi,SECTORSIZE_LG2		; Convert to an offset
		add esi,[DiskBuf]
		mov edi,ebx
		pop es
		ret

.baddapa:
		mov ax,0100h		; Invalid command
		pop es
		pop ax			; Drop setup_regs return address
		ret

.overrun:
		mov ax,0200h		; "Address mark not found" =
					; LBA beyond end of disk
.error:
		and word [es:si+2],0	; No sectors transferred
		pop es
		pop ax
		ret

EDDEject:
		mov ax,0B200h		; Volume Not Removable
		ret
%if ELTORITO
ElToritoTerminate:
		TRACER 'T'
		mov ax,[cs:SavedAX]
		cmp al,1		; We only support query, not terminate
		jne ElToritoErr		; Fail
		cmp dl,7fh		; Terminate all?
		je .doit
		cmp dl,[cs:DriveNo]	; Terminate our drive?
		je .doit
		jmp ElToritoErr		; Fail
.doit:		mov es,P_DS		; Caller's DS:SI pointed to packet
		mov di,P_SI		; We'll use ES:DI
		mov si,CD_PKT.size	; First byte is packet size
		xor cx,0		; Empty our count
		;mov cl,[ds:si]		; We'll copy that many bytes
		mov cl,13h
		rep movsb		; Copy until CX is zero
		mov ax,0		; Success
		ret
ElToritoEmulate:
ElToritoBoot:
ElToritoCatalog:
ElToritoErr:
		TRACER '!'
		mov ax,100h		; Invalid parameter
		ret
%endif ; ELTORITO
%endif ; EDD

;
; INT 15h intercept routines
;
int15_e820:
		cmp edx,534D4150h	; "SMAP"
		jne oldint15
		cmp ecx,20		; Need 20 bytes
		jb err86
		push ds
		push cs
		pop ds
		push edx		; "SMAP"
		and ebx,ebx
		jne .renew
		mov ebx,E820Table
.renew:
		add bx,12		; Advance to next
		mov eax,[bx-4]		; Type
		and eax,eax		; Null type?
		jz .renew		; If so advance to next
		mov [es:di+16],eax
		mov eax,[bx-12]		; Start addr (low)
		mov edx,[bx-8]		; Start addr (high)
		mov [es:di],eax
		mov [es:di+4],edx
		mov eax,[bx]		; End addr (low)
		mov edx,[bx+4]		; End addr (high)
		sub eax,[bx-12]		; Derive the length
		sbb edx,[bx-8]
		mov [es:di+8],eax	; Length (low)
		mov [es:di+12],edx	; Length (high)
		cmp dword [bx+8],-1	; Type of next = end?
		jne .notdone
		xor ebx,ebx		; Done with table
.notdone:
		pop eax			; "SMAP"
		mov edx,eax		; Some systems expect eax = edx = SMAP
		mov ecx,20		; Bytes loaded
		pop ds
int15_success:
		mov byte [bp+6], 02h	; Clear CF
		pop bp
		iret

err86:
		mov byte [bp+6], 03h	; Set CF
		mov ah,86h
		pop bp
		iret

Int15Start:
		push bp
		mov bp,sp
		cmp ax,0E820h
		je near int15_e820
		cmp ax,0E801h
		je int15_e801
		cmp ax,0E881h
		je int15_e881
		cmp ah,88h
		je int15_88
oldint15:	pop bp
		jmp far [cs:OldInt15]

int15_e801:				; Get mem size for > 64 MB config
		mov ax,[cs:Mem1MB]
		mov cx,ax
		mov bx,[cs:Mem16MB]
		mov dx,bx
		jmp short int15_success

int15_e881:				; Get mem size for > 64 MB config
					; 32-bit code
		mov eax,[cs:Mem1MB]
		mov ecx,eax
		mov ebx,[cs:Mem16MB]
		mov edx,ebx
		jmp short int15_success

int15_88:				; Get extended mem size
		mov ax,[cs:MemInt1588]
		jmp short int15_success

;
; Routine to copy in/out of high memory
; esi = linear source address
; edi = linear target address
; ecx = 32-bit word count
;
; Assumes cs = ds = es
;
bcopy:
		push eax
		push ebx
		push edx
		push ebp

		mov bx, real_int15_stub

		test byte [ConfigFlags], CONFIG_RAW|CONFIG_SAFEINT
		jz .anymode		; Always do the real INT 15h

		smsw ax			; Unprivileged!
		test al,01h
		jnz .protmode		; Protmode -> do real INT 15h

.realmode:
		; Raw or Safeint mode, and we're in real mode...

		test byte [ConfigFlags], CONFIG_SAFEINT
		jnz .fakeint15

.raw:
		TRACER 'r'
		; We're in real mode, do it outselves

		pushfd			; <A>
		push ds			; <B>
		push es			; <C>

		cli
		cld

		xor ebx,ebx
		mov bx,cs
		shl ebx,4
		lea edx,[Shaker+ebx]
		mov [Shaker+2],edx

		; Test to see if A20 is enabled or not
		xor ax,ax
		mov ds,ax
		dec ax
		mov es,ax

		mov ax,[0]
		mov bx,ax
		xor bx,[es:10h]
		not ax
		mov [0],ax
		mov dx,ax
		xor dx,[es:10h]
		not ax
		mov [0],ax

		or dx,bx
		push dx			; <D> Save A20 status
		jnz .skip_a20e

		mov ax,2401h		; Enable A20
		int 15h
.skip_a20e:
		mov dl,[ConfigFlags]
		and dx,CONFIG_BIGRAW
		add dx,8
		; DX = 16 for BIGRAW, 8 for RAW
		;  8 is selector for a 64K flat segment,
		; 16 is selector for a 4GB flat segment.

		lgdt [cs:Shaker]
		mov eax,cr0
		or al,01h
		mov cr0,eax

		mov bx,16		; Large flat segment
		mov ds,bx
		mov es,bx

		a32 rep movsd

		; DX has the appropriate value to put in
		; the registers on return
		mov ds,dx
		mov es,dx

		and al,~01h
		mov cr0,eax

		pop dx			; <D> A20 status
		pop es			; <C>
		pop ds			; <B>

		and dx,dx
		jnz .skip_a20d
		mov ax,2400h		; Disable A20
		int 15h
.skip_a20d:
		popfd			; <A>
		jmp .done

.fakeint15:
		; We're in real mode with CONFIG_SAFEINT, invoke the
		; original INT 15h vector.  We used to test for the
		; INT 15h vector being unchanged here, but that is
		; *us*; however, the test was wrong for years (always
		; negative) so instead of fixing the test do what we
		; tested and don't bother probing.
		mov bx, fake_int15_stub

.protmode:
		TRACER 'p'
.anymode:

.copy_loop:
		push esi
		push edi
		push ecx
		cmp ecx,4000h
		jna .safe_size
		mov ecx,4000h
.safe_size:
		push ecx	; Transfer size this cycle
		mov eax, esi
		mov [Mover_src1], si
		shr eax, 16
		mov [Mover_src1+2], al
		mov [Mover_src2], ah
		mov eax, edi
		mov [Mover_dst1], di
		shr eax, 16
		mov [Mover_dst1+2], al
		mov [Mover_dst2], ah
		mov si,Mover
		mov ah, 87h
		shl cx,1	; Convert to 16-bit words
		call bx		; INT 15h stub
		pop eax		; Transfer size this cycle
		pop ecx
		pop edi
		pop esi
		jc .error
		lea esi,[esi+4*eax]
		lea edi,[edi+4*eax]
		sub ecx, eax
		jnz .copy_loop
		; CF = 0
.error:
.done:
		pop ebp
		pop edx
		pop ebx
		pop eax
		ret

real_int15_stub:
		int 15h
		cli		; Some BIOSes enable interrupts on INT 15h
		ret

fake_int15_stub:
		pushf
		call far [OldInt15]
		cli
		ret

%ifdef DEBUG_TRACERS
debug_tracer:	pushad
		pushfd
		mov bp,sp
		mov bx,[bp+9*4]
		mov al,[cs:bx]
		inc word [bp+9*4]
		mov ah,0Eh
		mov bx,7
		int 10h
		popfd
		popad
		ret

writehex2:	pushad
		pushfd
		mov cx,2
		ror eax,4
		jmp writehex_common
writehex4:	pushad
		pushfd
		mov cx,4
		ror eax,12
		jmp writehex_common
writehex8:	pushad
		pushfd
		mov cx,8
		ror eax,28
writehex_common:
.loop:		push cx
		push eax
		and al,0Fh
		cmp al,10
		jb .isdec
		add al,'a'-'0'-10
.isdec:		add al,'0'
		mov ah,0Eh
		mov bx,7
		int 10h
		pop eax
		rol eax,4
		pop cx
		loop .loop
		popfd
		popad
		ret
%endif

		section .data align=16
		alignb 2
Int13Funcs	dw Reset		; 00h - RESET
		dw GetStatus		; 01h - GET STATUS
		dw Read			; 02h - READ
		dw Write		; 03h - WRITE
		dw Verify		; 04h - VERIFY
		dw Invalid		; 05h - FORMAT TRACK
		dw Invalid		; 06h - FORMAT TRACK AND SET BAD FLAGS
		dw Invalid		; 07h - FORMAT DRIVE AT TRACK
		dw GetParms		; 08h - GET PARAMETERS
		dw InitWithParms	; 09h - INITIALIZE CONTROLLER WITH
					;	DRIVE PARAMETERS
		dw Invalid		; 0Ah
		dw Invalid		; 0Bh
		dw Seek			; 0Ch - SEEK TO CYLINDER
		dw Reset		; 0Dh - RESET HARD DISKS
		dw Invalid		; 0Eh
		dw Invalid		; 0Fh
		dw CheckIfReady		; 10h - CHECK IF READY
		dw Recalibrate		; 11h - RECALIBRATE
		dw Invalid		; 12h
		dw Invalid		; 13h
		dw Invalid		; 14h
		dw GetDriveType		; 15h - GET DRIVE TYPE
		dw DetectChange		; 16h - DETECT DRIVE CHANGE
%if EDD
		dw Invalid		; 17h
		dw Invalid		; 18h
		dw Invalid		; 19h
		dw Invalid		; 1Ah
		dw Invalid		; 1Bh
		dw Invalid		; 1Ch
		dw Invalid		; 1Dh
		dw Invalid		; 1Eh
		dw Invalid		; 1Fh
		dw Invalid		; 20h
		dw ReadMult		; 21h - READ MULTIPLE
		dw WriteMult		; 22h - WRITE MULTIPLE
		dw SetMode		; 23h - SET CONTROLLER FEATURES
		dw SetMode		; 24h - SET MULTIPLE MODE
		dw Invalid		; 25h - IDENTIFY DRIVE
		dw Invalid		; 26h
		dw Invalid		; 27h
		dw Invalid		; 28h
		dw Invalid		; 29h
		dw Invalid		; 2Ah
		dw Invalid		; 2Bh
		dw Invalid		; 2Ch
		dw Invalid		; 2Dh
		dw Invalid		; 2Eh
		dw Invalid		; 2Fh
		dw Invalid		; 30h
		dw Invalid		; 31h
		dw Invalid		; 32h
		dw Invalid		; 33h
		dw Invalid		; 34h
		dw Invalid		; 35h
		dw Invalid		; 36h
		dw Invalid		; 37h
		dw Invalid		; 38h
		dw Invalid		; 39h
		dw Invalid		; 3Ah
		dw Invalid		; 3Bh
		dw Invalid		; 3Ch
		dw Invalid		; 3Dh
		dw Invalid		; 3Eh
		dw Invalid		; 3Fh
		dw Invalid		; 40h
		dw EDDPresence		; 41h - EDD PRESENCE DETECT
		dw EDDRead		; 42h - EDD READ
		dw EDDWrite		; 43h - EDD WRITE
		dw EDDVerify		; 44h - EDD VERIFY
		dw EDDLock		; 45h - EDD LOCK/UNLOCK MEDIA
		dw EDDEject		; 46h - EDD EJECT
		dw EDDSeek		; 47h - EDD SEEK
		dw EDDGetParms		; 48h - EDD GET PARAMETERS
		dw EDDDetectChange	; 49h - EDD MEDIA CHANGE STATUS
%if ELTORITO				; EDD El Torito Functions
					; ELTORITO _must_ also have EDD
		dw ElToritoEmulate	; 4Ah - Initiate Disk Emulation
		dw ElToritoTerminate	; 4Bh - Terminate Disk Emulation
		dw ElToritoBoot		; 4Ch - Initiate Disk Emu. and Reboot
		dw ElToritoCatalog	; 4Dh - Return Boot Catalog
%endif ; ELTORITO
%endif ; EDD

Int13FuncsEnd	equ $
Int13FuncsCnt	equ (Int13FuncsEnd-Int13Funcs) >> 1


		alignb 8, db 0
Shaker		dw ShakerEnd-$-1	; Descriptor table limit
		dd 0			; Pointer to self
		dw 0

Shaker_RMDS:	dd 0x0000ffff		; 64K data segment
		dd 0x00009300

Shaker_DS:	dd 0x0000ffff		; 4GB data segment
		dd 0x008f9300

ShakerEnd	equ $

		alignb 8, db 0

Mover		dd 0, 0, 0, 0		; Must be zero
		dw 0ffffh		; 64 K segment size
Mover_src1:	db 0, 0, 0		; Low 24 bits of source addy
		db 93h			; Access rights
		db 00h			; Extended access rights
Mover_src2:	db 0			; High 8 bits of source addy
		dw 0ffffh		; 64 K segment size
Mover_dst1:	db 0, 0, 0		; Low 24 bits of target addy
		db 93h			; Access rights
		db 00h			; Extended access rights
Mover_dst2:	db 0			; High 8 bits of source addy
Mover_dummy2:	dd 0, 0, 0, 0		; More space for the BIOS

		alignb 16, db 0
mBFT:
; Fields common to all ACPI tables
		dd '    '		; ACPI signature ("mBFT")
					; This is filled-in by the installer
					; to avoid an accidentally valid mBFT
		dd mBFT_Len		; ACPI table length
		db 1			; ACPI revision
		db 0			; ACPI table checksum
		db 'MEMDSK'		; ACPI OEM ID
		db 'Syslinux'		; ACPI OEM table ID
		dd 0			; ACPI OEM revision
		dd 0			; ACPI ASL compiler vendor ID
		dd 0			; ACPI ASL compiler revision
; The next field is mBFT-specific and filled-in by the installer
		dd 0			; "Safe hook" physical address

; Note that the above ends on a DWORD boundary.
; The MDI has always started at such a boundary.
; Portions of the MDI are patched by the installer
MemDisk_Info	equ $			; Pointed to by installation check
MDI_Bytes	dw MDI_Len		; Total bytes in MDI structure
MDI_Version	db VERSION_MINOR, VERSION_MAJOR	; MEMDISK version

DiskBuf		dd 0			; Linear address of high memory disk
DiskSize	dd 0			; Size of disk in blocks
CommandLine	dw 0, 0			; Far pointer to saved command line

OldInt13	dd 0			; INT 13h in chain
OldInt15	dd 0			; INT 15h in chain

OldDosMem	dw 0			; Old position of DOS mem end
BootLoaderID	db 0			; Boot loader ID from header
		db 0			; pad

DPT_ptr		dw 0			; If nonzero, pointer to DPT
					; Original DPT pointer follows

MDI_Len		equ $-MemDisk_Info
mBFT_Len	equ $-mBFT		; mBFT includes the MDI

; ---- MDI structure ends here ---
DriveShiftLimit	db 0ffh			; Installer will probe for
					; a range of contiguous drives.
					; Any BIOS drives above this region
					; shall not be impacted by our
					; shifting behaviour
		db 0			; pad to a DWORD
		dw 0			; pad to a QWORD
MemInt1588	dw 0			; 1MB-65MB memory amount (1K)

Cylinders	dw 0			; Cylinder count
Heads		dw 0			; Head count
Sectors		dd 0			; Sector count (zero-extended)

Mem1MB		dd 0			; 1MB-16MB memory amount (1K)
Mem16MB		dd 0			; 16MB-4G memory amount (64K)

DriveNo		db 0			; Our drive number
DriveType	db 0			; Our drive type (floppies)
DriveCnt	db 0			; Drive count (from the BIOS)

ConfigFlags	db 0			; Bit 0 - readonly

MyStack		dw 0			; Offset of stack
StatusPtr	dw 0			; Where to save status (zeroseg ptr)

DPT		times 16 db 0		; BIOS parameter table pointer (floppies)
OldInt1E	dd 0			; Previous INT 1E pointer (DPT)

%if EDD
EDD_DPT:
.length		dw 30
.info		dw 0029h
		; Bit 0 - DMA boundaries handled transparently
		; Bit 3 - Device supports write verify
		; Bit 5 - Media is lockable
.cylinders	dd 0			; Filled in by installer
.heads		dd 0			; Filled in by installer
.sectors	dd 0			; Filled in by installer
.totalsize	dd 0, 0			; Filled in by installer
.bytespersec	dw SECTORSIZE
.eddtable	dw -1, -1		; Invalid DPTE pointer
.dpikey		dw 0BEDDh		; Device Path Info magic
.dpilen		db 2ch			; DPI len
.res1		db 0			; Reserved
.res2		dw 0			; Reserved
.bustype	dd 'MEM '		; Host bus type (4 bytes, space padded)
.inttype	dd 'MEMORY  '		; Interface type (8 bytes, spc. padded)
.intpath	dd 0, 0			; Interface path
.devpath	dd 0, 0, 0, 0		; Device path
.res3		db 0			; Reserved
.chksum		db 0			; DPI checksum

%if ELTORITO
; El Torito CD Specification Packet - mostly filled in by installer
CD_PKT:
.size		db 13h	; Packet size (19 bytes)
.type		db 0	; Boot media type (flags)
.driveno	db 0E0h	; INT 13h drive number
.controller	db 0	; Controller index
.start		dd 0	; Starting LBA of image
.devno		dw 0	; Device number
.user_buf	dw 0	; User buffer segment
.load_seg	dw 0	; Load segment
.sect_count	dw 0	; Emulated sectors to load
.geom1		db 0	; Cylinders bits 0 thru 7
.geom2		db 0	; Sects/track 0 thru 5, cyls 8, 9
.geom3		db 0	; Heads
%endif ; ELTORITO

%endif ; EDD

; End patch area

		alignb 4, db 0
Stack		dd 0			; Saved SS:ESP on invocation
		dw 0
SavedAX		dw 0			; AX saved on invocation
Recursive	dw 0			; Recursion counter

		alignb 4, db 0		; We *MUST* end on a dword boundary

E820Table	equ $			; The installer loads the E820 table here
TotalSize	equ $			; End pointer
