	bits 16
swap:
	push bx
	movzx bx,dl
	mov dl,[cs:bx+(table-$$)]
	pop bx
.jmp:	jmp 0:0
	nop
	nop
install:
	;; DS = CS, ES = 0
	mov edi,[es:si+4*0x13]
	mov [swap.jmp+1],edi
	mov di,[es:0x413]
	dec di
	mov [es:0x413],di
	shl edi,16+6
	mov [es:si+4*0x13],edi
	shr edi,16
	mov es,di
	xor di,di
	rep movsd
	mov si,0
	mov di,0
	mov ds,si
	mov es,di
	mov ecx,0
	mov esi,0
	mov edi,0
	jmp 0:0

	align 16
table:
