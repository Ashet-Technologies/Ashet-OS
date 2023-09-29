;
; Process a PXE interrupt
;
		section .text16

PXEIRQ_MAX	equ 100		; Max spurious interrupts in a timer tick

		global pxe_isr
pxe_isr:
		cld
		pusha
		push ds
		push es
		push fs
		push gs

		xor ax,ax
		mov ds,ax	
		mov es,ax

		mov bx,PXENV_UNDI_ISR
		mov di,pxenv_undi_isr_buf

		mov cx,pxenv_undi_isr_buf.size/2
		push di
		rep stosw
		pop di
		
		mov byte [pxenv_undi_isr_buf.funcflag],PXENV_UNDI_ISR_IN_START

		call pxenv
		mov ax,[__jiffies]
		jc .notus

		cmp word [pxenv_undi_isr_buf.funcflag],PXENV_UNDI_ISR_OUT_OURS
		jne .notus

		; Its ours - set the flag for the return to PM.
		; We need to EOI this ourselves, so that the
		; leftover BC doesn't get control.
		mov byte [pxe_irq_pending],1
		inc dword [pxe_irq_count]

		cmp byte [pxe_irq_vector], 8
		mov al,0x20		; Non-specific EOI
		jb .pri_pic

		out 0xA0, al		; Secondary PIC
.pri_pic:
		out 0x20,al		; Primary PIC

		mov [pxeirq_last],ax
		mov word [pxeirq_deadman],PXEIRQ_MAX

.exit:
		pop gs
		pop fs
		pop es
		pop ds
		popa
		iret

.notus:
		cmp ax,[pxeirq_last]
		jne .reset_timeout
		dec word [pxeirq_deadman]
		jz .timeout

.chain:
		pop gs
		pop fs
		pop es
		pop ds
		popa
		jmp 0:0
		global pxe_irq_chain
pxe_irq_chain	equ $-4

.reset_timeout:
		mov [pxeirq_last],ax
		mov word [pxeirq_deadman],PXEIRQ_MAX
		jmp .chain

		; Too many spurious interrupts, shut off the interrupts
		; and go to polling mode
.timeout:
		mov al,[pxe_irq_vector]
		mov dx,21h
		movzx cx,al
		shl cx,7-3
		add dx,cx
		and al,7
		xchg ax,cx
		mov ch,1
		shl ch,cl
		in al,dx
		or al,ch
		out dx,al
		or byte [pxe_need_poll],1
		jmp .exit


; Emulate a PXE interrupt from the polling thread
		global pxe_poll
pxe_poll:
		pushf
		cli
		cld
		pusha
		push ds
		push es
		push fs
		push gs

		mov bx,PXENV_UNDI_ISR
		mov di,pxenv_undi_isr_buf

		mov cx,pxenv_undi_isr_buf.size/2
		push di
		rep stosw
		pop di
		
		mov byte [pxenv_undi_isr_buf.funcflag],PXENV_UNDI_ISR_IN_START

		call pxenv
		jc .notus

		cmp word [pxenv_undi_isr_buf.funcflag],PXENV_UNDI_ISR_OUT_OURS
		jne .notus

		; Its ours - set the flag for the return to PM.
		; We need to EOI this ourselves, so that the
		; leftover BC doesn't get control.
		mov byte [pxe_irq_pending],1

.notus:
		pop gs
		pop fs
		pop es
		pop ds
		popa
		popf
		ret

		section .bss16
		alignb 4
pxenv_undi_isr_buf:
.status:	resw 1
.funcflag:	resw 1
.bufferlength:	resw 1
.framelen:	resw 1
.framehdrlen:	resw 1
.frame:		resw 2
.prottype:	resb 1
.pkttype:	resb 1
.size		equ $-pxenv_undi_isr_buf

		alignb 4
pxeirq_last	resw 1
pxeirq_deadman	resw 1

		global pxe_irq_count
pxe_irq_count	resd 1			; PXE IRQ counter
		global pxe_irq_vector
pxe_irq_vector	resb 1			; PXE IRQ vector
		global pxe_irq_pending
pxe_irq_pending	resb 1			; IRQ pending flag
		global pxe_need_poll
pxe_need_poll	resb 1			; Bit 0 = need polling
					; Bit 1 = polling active

		section .text16
