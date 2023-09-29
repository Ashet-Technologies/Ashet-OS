;
; strcpy: Copy DS:SI -> ES:DI up to and including a null byte;
;	  on exit SI and DI point to the byte *after* the null byte
;
		section .text16

strcpy:		push ax
.loop:		lodsb
		stosb
		and al,al
		jnz .loop
		pop ax
		ret
