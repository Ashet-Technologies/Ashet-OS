;;
;; pmcall.inc
;;
;; Macros for the stack frame set up by pm_call, assuming ebp is left
;; as the RM frame pointer.
;;

%ifndef PMCALL_INC
%define PMCALL_INC

%define RM_GS		word [ebp]
%define RM_FS		word [ebp+2]
%define RM_ES		word [ebp+4]
%define RM_DS		word [ebp+6]

%define RM_EDI		dword [ebp+8]
%define RM_DI		word [ebp+8]
%define RM_HDI		word [ebp+10]
%define RM_DIL		byte [ebp+8]
%define RM_DIH		byte [ebp+9]

%define RM_ESI		dword [ebp+12]
%define RM_SI		word [ebp+12]
%define RM_HSI		word [ebp+14]
%define RM_SIL		byte [ebp+12]
%define RM_SIH		byte [ebp+13]

%define RM_EBP		dword [ebp+16]
%define RM_BP		word [ebp+16]
%define RM_HBP		word [ebp+18]
%define RM_BPL		byte [ebp+16]
%define RM_BPH		byte [ebp+17]

%define RM_EBX		dword [ebp+24]
%define RM_BX		word [ebp+24]
%define RM_HBX		word [ebp+26]
%define RM_BL		byte [ebp+24]
%define RM_BH		byte [ebp+25]

%define RM_EDX		dword [ebp+28]
%define RM_DX		word [ebp+28]
%define RM_HDX		word [ebp+30]
%define RM_DL		byte [ebp+28]
%define RM_DH		byte [ebp+29]

%define RM_ECX		dword [ebp+32]
%define RM_CX		word [ebp+32]
%define RM_HCX		word [ebp+34]
%define RM_CL		byte [ebp+32]
%define RM_CH		byte [ebp+33]

%define RM_EAX		dword [ebp+36]
%define RM_AX		word [ebp+36]
%define RM_HAX		word [ebp+38]
%define RM_AL		byte [ebp+36]
%define RM_AH		byte [ebp+37]

%define RM_EFLAGS	dword [ebp+40]
%define RM_FLAGS	word [ebp+40]
%define RM_HFLAGS	word [ebp+42]
%define RM_FLAGSL	byte [ebp+40]
%define RM_FLAGSH	byte [ebp+41]

; Convenience macro to call a PM function
%macro	pm_call	1
	push dword %1
	call _pm_call
%endmacro

%endif ; PMCALL_INC
