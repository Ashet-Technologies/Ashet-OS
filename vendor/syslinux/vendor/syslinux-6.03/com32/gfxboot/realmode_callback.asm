		bits 16

		section .text

		; must be filled in
f_buf_size	dw 0
f_buf_seg	dw 0


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
gfx_cb:
		push cs
		pop ds

		cmp al,cb_len
		jae gfx_cb_80

		movzx bx,al
		add bx,bx
		call word [bx+cb_table]
		jmp gfx_cb_90

gfx_cb_80:
		mov al,0ffh
gfx_cb_90:
		retf


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; Return status info.
;
; return:
;  edx		filename buffer (64 bytes)
;
cb_status:
		mov edx,cs
		shl edx,4
		add edx,f_name
		xor al,al
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; Open file.
;
; return:
;    al		0: ok, 1: file not found
;   ecx		file length (al = 0)
;
cb_fopen:
		mov si,f_name
		push ds
		pop es
		mov ax,6
		int 22h
		xchg edx,eax
		mov al,1
		jc cb_fopen_90
		cmp cx,[f_buf_size]
		ja cb_fopen_90
		or cx,cx
		jz cb_fopen_90
		mov [f_block_size],cx
		or edx,edx
		jz cb_fopen_90
		mov [f_handle],si
		mov [f_size],edx
		mov ecx,edx
		mov ax,[f_buf_size]
		cwd
		div word [f_block_size]
		mov [f_blocks],ax

		xor al,al
cb_fopen_90:
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; Read next chunk.
;
; return:
;   edx		buffer address (linear)
;   ecx		data length (< 64k)
;
cb_fread:
		xor ecx,ecx
		mov si,[f_handle]
		or si,si
		jz cb_fread_80
		mov cx,[f_blocks]
		mov es,[f_buf_seg]
		xor bx,bx
		mov ax,7
		int 22h
		mov [f_handle],si
		mov al,1
		jc cb_fread_90
cb_fread_80:
		xor al,al
cb_fread_90:
		movzx edx,word [f_buf_seg]
		shl edx,4
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; Return current working directory.
;
; return:
;  edx		filename
;
cb_getcwd:
		mov ax,1fh
		int 22h
		mov edx,es
		shl edx,4
		movzx ebx,bx
		add edx,ebx
		xor al,al
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; Set current working directory.
;
cb_chdir:
		mov bx,f_name
		push ds
		pop es
		mov ax,25h
		int 22h
		xor al,al
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; read sector
;
;  edx		sector
;
; return:
;  edx		buffer (linear address)
;
;  Note: does not return on error!
;
cb_readsector:
		xor edi,edi
		xor esi,esi
		mov cx,1
		mov es,[f_buf_seg]
		xor bx,bx
		mov ax,19h
		int 22h
		movzx edx,word [f_buf_seg]
		shl edx,4
		xor al,al
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; Re-read fs structures.
;
cb_mount:
		mov ax,26h
		int 22h
		setc al
		ret


; - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;
		align 2, db 0

cb_table	dw cb_status
		dw cb_fopen
		dw cb_fread
		dw cb_getcwd
		dw cb_chdir
		dw cb_readsector
		dw cb_mount
cb_len		equ ($-cb_table)/2

f_handle	dw 0
f_block_size	dw 0
f_blocks	dw 0
f_size		dd 0
f_name		times 64 db 0
f_name_len	equ $ - f_name

