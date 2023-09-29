		section .text16
		global local_boot16:function hidden
local_boot16:
		mov cx,0
		mov ss,cx
		mov sp,7C00h
		jmp 0:07C00h
