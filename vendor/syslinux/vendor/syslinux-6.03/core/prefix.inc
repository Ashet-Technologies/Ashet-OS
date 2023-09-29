;
; The prefix is a small structure that prefaces the actual code;
; it gives the compression program necessary information.
;

		section .prefix		nowrite progbits align=16
pfx_start	dd _start		; Start of raw chunk
pfx_compressed	dd __pm_code_lma	; Start of compressed chunk
pfx_cdatalen	dd lzo_data_size	; Pointer to compressed size field
%if IS_ISOLINUX
pfx_checksum	dd bi_length		; File length and checksum fields
%else
pfx_checksum	dd 0			; No checksum
%endif
pfx_maxlma	dd MaxLMA		; Maximum size

		section .text16
