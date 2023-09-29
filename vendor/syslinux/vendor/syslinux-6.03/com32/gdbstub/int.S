    .section ".text","ax"

#define SIGTRAP 5

#define SIZEOF_I386_REGS    32
#define SIZEOF_I386_FLAGS   4

/* When invoked, the stack contains: eflags, cs, eip, signo. */
#define IH_OFFSET_GDB_REGS ( 0 )
#define IH_OFFSET_GDB_EIP ( IH_OFFSET_GDB_REGS + SIZEOF_I386_REGS )
#define IH_OFFSET_GDB_EFLAGS ( IH_OFFSET_GDB_EIP + 4 )
#define IH_OFFSET_GDB_SEG_REGS ( IH_OFFSET_GDB_EFLAGS + SIZEOF_I386_FLAGS )
#define IH_OFFSET_GDB_END ( IH_OFFSET_GDB_SEG_REGS + 6 * 4 )
#define IH_OFFSET_OLD_EIP ( IH_OFFSET_GDB_END )
#define IH_OFFSET_OLD_CS ( IH_OFFSET_OLD_EIP + 4 )
#define IH_OFFSET_OLD_EFLAGS ( IH_OFFSET_OLD_CS + 4 )
#define IH_OFFSET_END ( IH_OFFSET_OLD_EFLAGS + 4 )

/* We also access the stack whilst still storing or restoring
 * the register snapshot.  Since ESP is in flux, we need
 * special offsets.
 */
#define IH_OFFSET_FLUX_OLD_CS ( IH_OFFSET_OLD_CS - 44 )
#define IH_OFFSET_FLUX_OLD_EFLAGS ( IH_OFFSET_OLD_EFLAGS - 40 )
#define IH_OFFSET_FLUX_OLD_EIP ( IH_OFFSET_OLD_EIP - 36 )
#define IH_OFFSET_FLUX_END ( IH_OFFSET_END - 20 )

    .global int_handler
int_handler:
	/* Store CPU state in GDB register snapshot */
	pushw	$0
	pushw	%gs
	pushw	$0
	pushw	%fs
	pushw	$0
	pushw	%es
	pushw	$0
	pushw	%ds
	pushw	$0
	pushw	%ss
	pushw	$0
	pushw	IH_OFFSET_FLUX_OLD_CS + 2(%esp)
	pushl	IH_OFFSET_FLUX_OLD_EFLAGS(%esp)
	pushl	IH_OFFSET_FLUX_OLD_EIP(%esp)
	pushl	%edi
	pushl	%esi
	pushl	%ebp
	leal	IH_OFFSET_FLUX_END(%esp), %edi
	pushl	%edi /* old ESP */
	pushl	%ebx
	pushl	%edx
	pushl	%ecx
	pushl	%eax

	/* Call GDB stub exception handler */
    movl    $SIGTRAP, %eax
	movl	%esp, %edx
	call	gdbstub_handler

	/* Restore CPU state from GDB register snapshot */
	popl	%eax
	popl	%ecx
	popl	%edx
	popl	%ebx
	addl	$4, %esp /* Changing ESP currently not supported */
	popl	%ebp
	popl	%esi
	popl	%edi
	popl	IH_OFFSET_FLUX_OLD_EIP(%esp)
	popl	IH_OFFSET_FLUX_OLD_EFLAGS(%esp)
	popl	IH_OFFSET_FLUX_OLD_CS(%esp)
	popl	%ss
	popl	%ds
	popl	%es
	popl	%fs
	popl	%gs
	iret
